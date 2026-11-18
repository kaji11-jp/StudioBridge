import fs from 'node:fs/promises';
import path from 'node:path';
import type { StateMap, FileState, ScriptClassName } from '../types.js';
import { computeHash, normalizeContent } from '../utils/hash.js';
import { normalizeRelPath } from '../utils/script-classifier.js';

export class StateManager {
  private projectRoot: string;
  private dotDir: string;
  private stateFilePath: string;
  private cacheDir: string;
  private state: StateMap = { version: '2.0.0', files: {} };

  constructor(projectRoot: string) {
    this.projectRoot = projectRoot;
    this.dotDir = path.join(projectRoot, '.studiobridge');
    this.stateFilePath = path.join(this.dotDir, 'state.json');
    this.cacheDir = path.join(this.dotDir, 'cache');
  }

  async init(): Promise<void> {
    await fs.mkdir(this.dotDir, { recursive: true });
    await fs.mkdir(this.cacheDir, { recursive: true });

    try {
      const data = await fs.readFile(this.stateFilePath, 'utf8');
      const loaded = JSON.parse(data) as StateMap;
      if (loaded.files) {
        this.state = loaded;
      }
    } catch {
      // File does not exist yet or is invalid, will save fresh state
      await this.saveState();
    }
  }

  async saveState(): Promise<void> {
    try {
      await fs.writeFile(
        this.stateFilePath,
        JSON.stringify(this.state, null, 2),
        'utf8'
      );
    } catch (err) {
      console.error('Failed to save state.json:', err);
    }
  }

  getFileState(relPath: string): FileState | undefined {
    return this.state.files[normalizeRelPath(relPath)];
  }

  /**
   * Checks if the content matches the last known hash (echo suppression)
   */
  isEcho(relPath: string, content: string): boolean {
    const currentHash = computeHash(content);
    const existing = this.getFileState(relPath);
    return existing?.hash === currentHash;
  }

  /**
   * Updates state and caches the base content
   */
  async updateFile(
    relPath: string,
    content: string,
    className: ScriptClassName
  ): Promise<FileState> {
    const normPath = normalizeRelPath(relPath);
    const hash = computeHash(content);
    const fileState: FileState = {
      path: normPath,
      className,
      hash,
      lastSyncedAt: Date.now()
    };

    this.state.files[normPath] = fileState;
    await this.saveState();
    await this.saveBaseCache(normPath, content);
    return fileState;
  }

  async removeFile(relPath: string): Promise<void> {
    const normPath = normalizeRelPath(relPath);
    delete this.state.files[normPath];
    await this.saveState();
    await this.deleteBaseCache(normPath);
  }

  getCachePath(relPath: string): string {
    const normPath = normalizeRelPath(relPath);
    // Replace slashes with double underscore or mirror structure
    return path.join(this.cacheDir, normPath.replace(/\//g, '___'));
  }

  async saveBaseCache(relPath: string, content: string): Promise<void> {
    try {
      const cacheFile = this.getCachePath(relPath);
      await fs.writeFile(cacheFile, normalizeContent(content), 'utf8');
    } catch (err) {
      console.error(`Failed to cache base content for ${relPath}:`, err);
    }
  }

  async getBaseCache(relPath: string): Promise<string | null> {
    try {
      const cacheFile = this.getCachePath(relPath);
      return await fs.readFile(cacheFile, 'utf8');
    } catch {
      return null;
    }
  }

  async deleteBaseCache(relPath: string): Promise<void> {
    try {
      const cacheFile = this.getCachePath(relPath);
      await fs.unlink(cacheFile);
    } catch {
      // Ignore if cache file didn't exist
    }
  }

  getAllFiles(): Record<string, FileState> {
    return { ...this.state.files };
  }
}
