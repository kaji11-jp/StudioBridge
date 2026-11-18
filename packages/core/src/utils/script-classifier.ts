import path from 'node:path';
import type { ScriptClassName } from '../types.js';

export const WATCHED_DIRECTORIES = [
  'ReplicatedStorage',
  'ServerScriptService',
  'StarterPlayer'
];

export const IGNORED_PATTERNS = [
  /(^|[/\\])\../, // Hidden files/folders (.git, .vscode, .studiobridge, etc.)
  /\.conflict-[\w-]+\.luau$/, // Conflict backup files
  /\.DS_Store$/
];

/**
 * Normalize relative path to forward slashes
 */
export function normalizeRelPath(filePath: string): string {
  return filePath.replace(/\\/g, '/');
}

/**
 * Checks if a relative path belongs to one of the watched service directories
 */
export function isWatchedPath(relPath: string): boolean {
  const normalized = normalizeRelPath(relPath);
  return WATCHED_DIRECTORIES.some(dir => normalized === dir || normalized.startsWith(`${dir}/`));
}

/**
 * Checks if a file path is a Luau script and not ignored
 */
export function isSyncableScript(relPath: string): boolean {
  const normalized = normalizeRelPath(relPath);
  if (!normalized.endsWith('.luau')) return false;
  if (IGNORED_PATTERNS.some(pattern => pattern.test(normalized))) return false;
  return isWatchedPath(normalized);
}

/**
 * Determines the ScriptClassName based on specification priority:
 * 1. Existing instance / state className
 * 2. Magic comment in source code (--!server, --!client, --!module)
 * 3. Directory location
 */
export function determineClassName(
  relPath: string,
  source?: string,
  existingClassName?: ScriptClassName
): ScriptClassName {
  if (existingClassName) {
    return existingClassName;
  }

  const normalized = normalizeRelPath(relPath);

  // Check magic comment on the first line
  if (source) {
    const firstLine = source.split(/\r?\n/)[0]?.trim();
    if (firstLine === '--!server') return 'Script';
    if (firstLine === '--!client') return 'LocalScript';
    if (firstLine === '--!module') return 'ModuleScript';
  }

  // Check parent folder name
  const dirParts = path.dirname(normalized).split('/');
  const parentDir = dirParts[dirParts.length - 1];
  if (parentDir === 'Modules' || parentDir === 'Libs') {
    return 'ModuleScript';
  }

  // Check service root
  if (normalized.startsWith('ServerScriptService/')) {
    return 'Script';
  }
  if (
    normalized.startsWith('StarterPlayer/StarterPlayerScripts/') ||
    normalized.startsWith('StarterPlayer/StarterCharacterScripts/') ||
    normalized.startsWith('StarterPlayer/')
  ) {
    return 'LocalScript';
  }
  if (normalized.startsWith('ReplicatedStorage/')) {
    return 'ModuleScript';
  }

  return 'ModuleScript';
}
