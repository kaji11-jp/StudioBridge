import { EventEmitter } from 'node:events';
import type { BridgeConfig, ServerEventPayload } from './types.js';
import { StateManager } from './state/state-manager.js';
import { ContextManager } from './context/context-manager.js';
import { SourcemapGenerator } from './sourcemap/sourcemap-generator.js';
import { FileWatcher } from './watcher/file-watcher.js';
import { BridgeServer } from './server/http-server.js';

export class BridgeEngine extends EventEmitter {
  public readonly config: BridgeConfig;
  public readonly stateManager: StateManager;
  public readonly contextManager: ContextManager;
  public readonly sourcemapGenerator: SourcemapGenerator;
  public readonly fileWatcher: FileWatcher;
  public readonly server: BridgeServer;
  private isRunning: boolean = false;

  constructor(config: BridgeConfig) {
    super();
    this.config = config;

    this.stateManager = new StateManager(config.projectRoot);
    this.contextManager = new ContextManager(config.projectRoot);
    this.sourcemapGenerator = new SourcemapGenerator(config.projectRoot);
    this.fileWatcher = new FileWatcher(
      {
        projectRoot: config.projectRoot,
        debounceMs: config.debounceMs ?? 150
      },
      this.stateManager
    );
    this.server = new BridgeServer(
      {
        port: config.port ?? 34872,
        host: config.host ?? '127.0.0.1',
        projectRoot: config.projectRoot
      },
      this.stateManager,
      this.contextManager,
      this.sourcemapGenerator,
      this.fileWatcher
    );

    // Forward events
    this.fileWatcher.on('change', event => {
      this.emit('localChange', event);
      this.server.broadcastEvent({
        type: 'sync',
        data: { direction: 'localToStudio', event },
        timestamp: new Date().toISOString()
      });
      // Re-generate sourcemap on local changes
      this.sourcemapGenerator.generate(this.stateManager.getAllFiles()).catch(() => {});
    });
  }

  async start(): Promise<void> {
    if (this.isRunning) return;

    await this.stateManager.init();
    await this.contextManager.init();
    await this.sourcemapGenerator.generate(this.stateManager.getAllFiles());
    await this.fileWatcher.start();
    await this.server.start();

    this.isRunning = true;
    this.emit('started', { port: this.config.port ?? 34872 });
  }

  async stop(): Promise<void> {
    if (!this.isRunning) return;

    await this.fileWatcher.stop();
    await this.server.stop();

    this.isRunning = false;
    this.emit('stopped');
  }

  get running(): boolean {
    return this.isRunning;
  }
}
