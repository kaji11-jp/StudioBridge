export type ScriptClassName = 'Script' | 'LocalScript' | 'ModuleScript';

export interface SyncEvent {
  type: 'upsert' | 'delete';
  path: string; // e.g., "ReplicatedStorage/Shared/Config.luau"
  className?: ScriptClassName;
  hash?: string;
  source?: string;
}

export interface StudioLogEntry {
  timestamp: string;
  level: 'INFO' | 'WARN' | 'ERROR';
  message: string;
}

export interface FileState {
  path: string;
  className: ScriptClassName;
  hash: string;
  lastSyncedAt: number;
}

export interface StateMap {
  version: string;
  files: Record<string, FileState>;
}

export interface BridgeConfig {
  projectRoot: string;
  port?: number;
  host?: string;
  debounceMs?: number;
}

export interface ServerEventPayload {
  type: 'status' | 'sync' | 'conflict' | 'log' | 'tree' | 'error';
  data: any;
  timestamp: string;
}

export interface RojoSourcemapNode {
  name: string;
  className: string;
  filePaths?: string[];
  children?: RojoSourcemapNode[];
}
