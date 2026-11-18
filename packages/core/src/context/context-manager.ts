import fs from 'node:fs/promises';
import path from 'node:path';
import type { StudioLogEntry } from '../types.js';

export class ContextManager {
  private projectRoot: string;
  private dotDir: string;
  private logPath: string;
  private treePath: string;
  private logBuffer: string[] = [];
  private maxLogLines = 1000;

  constructor(projectRoot: string) {
    this.projectRoot = projectRoot;
    this.dotDir = path.join(projectRoot, '.studiobridge');
    this.logPath = path.join(this.dotDir, 'output.log');
    this.treePath = path.join(this.dotDir, 'tree.txt');
  }

  async init(): Promise<void> {
    await fs.mkdir(this.dotDir, { recursive: true });

    // Load initial logs if file exists
    try {
      const content = await fs.readFile(this.logPath, 'utf8');
      this.logBuffer = content.split('\n').filter(Boolean);
      if (this.logBuffer.length > this.maxLogLines) {
        this.logBuffer = this.logBuffer.slice(-this.maxLogLines);
      }
    } catch {
      this.logBuffer = [];
    }
  }

  async appendLogs(entries: StudioLogEntry[]): Promise<void> {
    const formatted = entries.map(
      e => `[${e.timestamp}] [${e.level}] ${e.message}`
    );
    this.logBuffer.push(...formatted);

    if (this.logBuffer.length > this.maxLogLines) {
      this.logBuffer = this.logBuffer.slice(-this.maxLogLines);
    }

    try {
      await fs.writeFile(this.logPath, this.logBuffer.join('\n') + '\n', 'utf8');
    } catch (err) {
      console.error('Failed to write output.log:', err);
    }
  }

  async getLogs(): Promise<string> {
    return this.logBuffer.join('\n');
  }

  async clearLogs(): Promise<void> {
    this.logBuffer = [];
    try {
      await fs.writeFile(this.logPath, '', 'utf8');
    } catch (err) {
      console.error('Failed to clear output.log:', err);
    }
  }

  async setTree(treeText: string): Promise<void> {
    try {
      await fs.writeFile(this.treePath, treeText, 'utf8');
    } catch (err) {
      console.error('Failed to write tree.txt:', err);
    }
  }

  async getTree(): Promise<string> {
    try {
      return await fs.readFile(this.treePath, 'utf8');
    } catch {
      return '';
    }
  }
}
