import path from 'node:path';
import fs from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import { watch, type FSWatcher } from 'chokidar';
import type { SyncEvent, ScriptClassName } from '../types.js';
import type { StateManager } from '../state/state-manager.js';
import {
  WATCHED_DIRECTORIES,
  determineClassName,
  isSyncableScript,
  normalizeRelPath
} from '../utils/script-classifier.js';
import { computeHash } from '../utils/hash.js';

export interface FileWatcherOptions {
  projectRoot: string;
  debounceMs?: number;
}

export class FileWatcher extends EventEmitter {
  private projectRoot: string;
  private debounceMs: number;
  private stateManager: StateManager;
  private watcher: FSWatcher | null = null;
  private pendingChanges = new Map<string, { type: 'upsert' | 'delete'; timer: NodeJS.Timeout }>();
  private queue: SyncEvent[] = [];

  constructor(options: FileWatcherOptions, stateManager: StateManager) {
    super();
    this.projectRoot = options.projectRoot;
    this.debounceMs = options.debounceMs ?? 150;
    this.stateManager = stateManager;
  }

  async start(): Promise<void> {
    const watchPaths = WATCHED_DIRECTORIES.map(dir => path.join(this.projectRoot, dir));

    this.watcher = watch(watchPaths, {
      ignored: /(^|[/\\])\../, // ignore dotfiles
      persistent: true,
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 100,
        pollInterval: 50
      }
    });

    this.watcher.on('add', (filePath: string) => this.onFileChange('upsert', filePath));
    this.watcher.on('change', (filePath: string) => this.onFileChange('upsert', filePath));
    this.watcher.on('unlink', (filePath: string) => this.onFileChange('delete', filePath));
  }

  async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
    }
    for (const item of this.pendingChanges.values()) {
      clearTimeout(item.timer);
    }
    this.pendingChanges.clear();
  }

  private onFileChange(type: 'upsert' | 'delete', fullPath: string): void {
    const relPath = normalizeRelPath(path.relative(this.projectRoot, fullPath));
    if (!isSyncableScript(relPath)) return;

    if (this.pendingChanges.has(relPath)) {
      clearTimeout(this.pendingChanges.get(relPath)!.timer);
    }

    const timer = setTimeout(async () => {
      this.pendingChanges.delete(relPath);
      await this.processFileChange(type, relPath, fullPath);
    }, this.debounceMs);

    this.pendingChanges.set(relPath, { type, timer });
  }

  private async processFileChange(
    type: 'upsert' | 'delete',
    relPath: string,
    fullPath: string
  ): Promise<void> {
    if (type === 'delete') {
      const existing = this.stateManager.getFileState(relPath);
      if (!existing) return; // Already deleted or unknown

      await this.stateManager.removeFile(relPath);
      this.enqueue({ type: 'delete', path: relPath });
      this.emit('change', { type: 'delete', path: relPath });
      return;
    }

    // Upsert
    try {
      const content = await fs.readFile(fullPath, 'utf8');

      // Check echo
      if (this.stateManager.isEcho(relPath, content)) {
        return;
      }

      const existingState = this.stateManager.getFileState(relPath);
      const className = determineClassName(relPath, content, existingState?.className);
      const hash = computeHash(content);

      // Update state and base cache
      await this.stateManager.updateFile(relPath, content, className);

      const event: SyncEvent = {
        type: 'upsert',
        path: relPath,
        className,
        hash,
        source: content
      };

      this.enqueue(event);
      this.emit('change', event);
    } catch (err: any) {
      if (err.code !== 'ENOENT') {
        console.error(`Error processing file change for ${relPath}:`, err);
      }
    }
  }

  private enqueue(event: SyncEvent): void {
    // Remove existing event for same path if pending in queue
    this.queue = this.queue.filter(e => e.path !== event.path);
    this.queue.push(event);
  }

  /**
   * Sorts queue in order:
   * 1. Delete events (deepest first)
   * 2. Upsert events (shallowest first)
   */
  drainQueue(): SyncEvent[] {
    if (this.queue.length === 0) return [];

    const deletes = this.queue
      .filter(e => e.type === 'delete')
      .sort((a, b) => b.path.split('/').length - a.path.split('/').length);

    const upserts = this.queue
      .filter(e => e.type === 'upsert')
      .sort((a, b) => a.path.split('/').length - b.path.split('/').length);

    const result = [...deletes, ...upserts];
    this.queue = [];
    return result;
  }

  hasPending(): boolean {
    return this.queue.length > 0;
  }
}
