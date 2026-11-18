import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import type { SyncEvent, StudioLogEntry, ServerEventPayload, ScriptClassName } from '../types.js';
import type { StateManager } from '../state/state-manager.js';
import type { ContextManager } from '../context/context-manager.js';
import type { SourcemapGenerator } from '../sourcemap/sourcemap-generator.js';
import type { FileWatcher } from '../watcher/file-watcher.js';
import { perform3WayMerge } from '../merge/diff3-merger.js';
import { determineClassName, isWatchedPath, normalizeRelPath } from '../utils/script-classifier.js';
import { computeHash, normalizeContent } from '../utils/hash.js';

export interface HttpServerOptions {
  port?: number;
  host?: string;
  projectRoot: string;
}

export class BridgeServer extends EventEmitter {
  private server: http.Server | null = null;
  private port: number;
  private host: string;
  private projectRoot: string;
  private stateManager: StateManager;
  private contextManager: ContextManager;
  private sourcemapGenerator: SourcemapGenerator;
  private fileWatcher: FileWatcher;
  private sseClients: Set<http.ServerResponse> = new Set();
  private lastStudioConnectedAt: number = 0;

  constructor(
    options: HttpServerOptions,
    stateManager: StateManager,
    contextManager: ContextManager,
    sourcemapGenerator: SourcemapGenerator,
    fileWatcher: FileWatcher
  ) {
    super();
    this.port = options.port ?? 34872;
    this.host = options.host ?? '127.0.0.1';
    this.projectRoot = options.projectRoot;
    this.stateManager = stateManager;
    this.contextManager = contextManager;
    this.sourcemapGenerator = sourcemapGenerator;
    this.fileWatcher = fileWatcher;
  }

  async start(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server = http.createServer(async (req, res) => {
        // Set CORS headers
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

        if (req.method === 'OPTIONS') {
          res.writeHead(204);
          res.end();
          return;
        }

        const url = new URL(req.url ?? '/', `http://${req.headers.host || '127.0.0.1'}`);
        const pathname = url.pathname;

        try {
          await this.handleRoute(pathname, req, res);
        } catch (err: any) {
          console.error(`Error handling ${req.method} ${pathname}:`, err);
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: err.message || 'Internal Server Error' }));
        }
      });

      this.server.on('error', reject);
      this.server.listen(this.port, this.host, () => {
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    for (const client of this.sseClients) {
      client.end();
    }
    this.sseClients.clear();

    if (this.server) {
      await new Promise<void>(resolve => {
        this.server!.close(() => resolve());
      });
      this.server = null;
    }
  }

  /**
   * Broadcasts Server-Sent Event to connected UI clients
   */
  broadcastEvent(event: ServerEventPayload): void {
    const data = `data: ${JSON.stringify(event)}\n\n`;
    for (const client of this.sseClients) {
      try {
        client.write(data);
      } catch {
        this.sseClients.delete(client);
      }
    }
  }

  private async handleRoute(pathname: string, req: http.IncomingMessage, res: http.ServerResponse): Promise<void> {
    // 1. GET /health
    if (pathname === '/health' && req.method === 'GET') {
      this.lastStudioConnectedAt = Date.now();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'ok',
        version: '2.0.0',
        name: 'StudioBridge'
      }));
      return;
    }

    // 2. GET /events (Server-Sent Events for UI / VS Code Extension)
    if (pathname === '/events' && req.method === 'GET') {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive'
      });
      res.write(': connected\n\n');
      this.sseClients.add(res);

      req.on('close', () => {
        this.sseClients.delete(res);
      });
      return;
    }

    // 3. POST /export (Initial Studio -> Local pull)
    if (pathname === '/export' && req.method === 'POST') {
      const body = await this.readJsonBody(req);
      const scripts = (body.scripts || []) as Array<{
        path: string;
        className: ScriptClassName;
        source: string;
      }>;

      for (const item of scripts) {
        const relPath = normalizeRelPath(item.path);
        if (!isWatchedPath(relPath)) continue;

        const fullPath = path.join(this.projectRoot, relPath);
        await fs.mkdir(path.dirname(fullPath), { recursive: true });
        await fs.writeFile(fullPath, item.source, 'utf8');

        await this.stateManager.updateFile(relPath, item.source, item.className);
      }

      await this.sourcemapGenerator.generate(this.stateManager.getAllFiles());

      this.broadcastEvent({
        type: 'sync',
        data: { action: 'export', count: scripts.length },
        timestamp: new Date().toISOString()
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, count: scripts.length }));
      return;
    }

    // 4. POST /push (Studio -> Local diffs)
    if (pathname === '/push' && req.method === 'POST') {
      this.lastStudioConnectedAt = Date.now();
      const body = await this.readJsonBody(req);
      const events = (body.events || []) as SyncEvent[];
      const results: any[] = [];

      for (const ev of events) {
        const relPath = normalizeRelPath(ev.path);
        if (!isWatchedPath(relPath)) continue;

        const fullPath = path.join(this.projectRoot, relPath);

        if (ev.type === 'delete') {
          try {
            await fs.unlink(fullPath);
          } catch {
            // Already removed
          }
          await this.stateManager.removeFile(relPath);
          results.push({ path: relPath, status: 'deleted' });
          continue;
        }

        // Upsert
        const remoteSource = ev.source ?? '';
        const remoteHash = ev.hash || computeHash(remoteSource);

        // Echo check
        if (this.stateManager.isEcho(relPath, remoteSource)) {
          results.push({ path: relPath, status: 'skipped_echo' });
          continue;
        }

        // Read local current content if exists
        let localSource: string | null = null;
        try {
          localSource = await fs.readFile(fullPath, 'utf8');
        } catch {
          localSource = null;
        }

        const baseSource = await this.stateManager.getBaseCache(relPath);
        const className = ev.className || determineClassName(relPath, remoteSource);

        if (localSource !== null && baseSource !== null && normalizeContent(localSource) !== normalizeContent(baseSource)) {
          // Local has uncommitted changes, 3-way merge is needed
          const merge = perform3WayMerge(baseSource, localSource, remoteSource);

          if (merge.hasConflict) {
            // Conflict occurred:
            // 1. Accept remote source into target file
            await fs.writeFile(fullPath, merge.mergedContent!, 'utf8');
            await this.stateManager.updateFile(relPath, merge.mergedContent!, className);

            // 2. Save local content to Target.conflict-<timestamp>.luau
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const ext = path.extname(fullPath);
            const baseFile = fullPath.slice(0, -ext.length);
            const conflictPath = `${baseFile}.conflict-${timestamp}${ext}`;
            await fs.writeFile(conflictPath, merge.conflictBackupContent!, 'utf8');

            const conflictRelPath = normalizeRelPath(path.relative(this.projectRoot, conflictPath));

            this.broadcastEvent({
              type: 'conflict',
              data: {
                path: relPath,
                conflictFile: conflictRelPath
              },
              timestamp: new Date().toISOString()
            });

            results.push({
              path: relPath,
              status: 'conflict',
              conflictFile: conflictRelPath
            });
            continue;
          } else {
            // Clean 3-way merge
            await fs.writeFile(fullPath, merge.mergedContent!, 'utf8');
            await this.stateManager.updateFile(relPath, merge.mergedContent!, className);

            results.push({ path: relPath, status: 'merged' });
            continue;
          }
        }

        // Standard update (no local conflict)
        await fs.mkdir(path.dirname(fullPath), { recursive: true });
        await fs.writeFile(fullPath, remoteSource, 'utf8');
        await this.stateManager.updateFile(relPath, remoteSource, className);
        results.push({ path: relPath, status: 'synced' });
      }

      await this.sourcemapGenerator.generate(this.stateManager.getAllFiles());

      this.broadcastEvent({
        type: 'sync',
        data: { action: 'push', results },
        timestamp: new Date().toISOString()
      });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, results }));
      return;
    }

    // 5. GET /poll (Studio polls local changes)
    if (pathname === '/poll' && req.method === 'GET') {
      this.lastStudioConnectedAt = Date.now();
      const events = this.fileWatcher.drainQueue();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ events }));
      return;
    }

    // 6. POST /logs, GET /logs, DELETE /logs
    if (pathname === '/logs') {
      if (req.method === 'POST') {
        const body = await this.readJsonBody(req);
        const entries = (body.logs || []) as StudioLogEntry[];
        await this.contextManager.appendLogs(entries);

        this.broadcastEvent({
          type: 'log',
          data: entries,
          timestamp: new Date().toISOString()
        });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, count: entries.length }));
        return;
      }
      if (req.method === 'GET') {
        const logs = await this.contextManager.getLogs();
        res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end(logs);
        return;
      }
      if (req.method === 'DELETE') {
        await this.contextManager.clearLogs();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true }));
        return;
      }
    }

    // 7. POST /tree, GET /tree
    if (pathname === '/tree') {
      if (req.method === 'POST') {
        const body = await this.readJsonBody(req);
        const treeText = typeof body === 'string' ? body : (body.tree || '');
        await this.contextManager.setTree(treeText);

        this.broadcastEvent({
          type: 'tree',
          data: { size: treeText.length },
          timestamp: new Date().toISOString()
        });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true }));
        return;
      }
      if (req.method === 'GET') {
        const tree = await this.contextManager.getTree();
        res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end(tree);
        return;
      }
    }

    // Not found
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Endpoint not found' }));
  }

  private readJsonBody(req: http.IncomingMessage): Promise<any> {
    return new Promise((resolve, reject) => {
      let data = '';
      req.on('data', chunk => {
        data += chunk;
      });
      req.on('end', () => {
        if (!data) return resolve({});
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          resolve(data);
        }
      });
      req.on('error', reject);
    });
  }
}
