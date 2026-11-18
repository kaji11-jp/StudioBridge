import crypto from 'node:crypto';

/**
 * Normalizes line endings to LF before hashing to prevent CRLF vs LF discrepancy
 * between Windows file systems and Roblox Studio.
 */
export function normalizeContent(content: string): string {
  return content.replace(/\r\n/g, '\n');
}

/**
 * Computes SHA-256 hash for content
 */
export function computeHash(content: string): string {
  const normalized = normalizeContent(content);
  return crypto.createHash('sha256').update(normalized, 'utf8').digest('hex');
}
