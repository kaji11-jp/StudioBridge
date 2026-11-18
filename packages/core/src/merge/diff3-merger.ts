import { merge as diff3Merge } from 'node-diff3';
import { normalizeContent } from '../utils/hash.js';

export interface MergeResult {
  hasConflict: boolean;
  mergedContent?: string;
  conflictBackupContent?: string;
}

/**
 * Performs a 3-way merge between Base, Local, and Remote sources.
 *
 * @param base The base content when last synchronized
 * @param local The current local file content
 * @param remote The incoming remote content from Roblox Studio
 */
export function perform3WayMerge(
  base: string,
  local: string,
  remote: string
): MergeResult {
  const normBase = normalizeContent(base).split('\n');
  const normLocal = normalizeContent(local).split('\n');
  const normRemote = normalizeContent(remote).split('\n');

  // diff3Merge(a, o, b): a = local, o = base (original), b = remote
  const mergeResult = diff3Merge(normLocal, normBase, normRemote);

  if (!mergeResult.conflict) {
    return {
      hasConflict: false,
      mergedContent: mergeResult.result.join('\n')
    };
  }

  // Conflict occurred:
  // Per specs: Accept remote to normalize sync, save local to .conflict-<timestamp>.luau
  return {
    hasConflict: true,
    mergedContent: normalizeContent(remote),
    conflictBackupContent: normalizeContent(local)
  };
}
