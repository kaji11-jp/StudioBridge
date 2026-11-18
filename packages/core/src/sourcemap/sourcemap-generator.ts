import fs from 'node:fs/promises';
import path from 'node:path';
import type { RojoSourcemapNode, ScriptClassName } from '../types.js';
import {
  WATCHED_DIRECTORIES,
  determineClassName,
  isSyncableScript,
  normalizeRelPath
} from '../utils/script-classifier.js';

export class SourcemapGenerator {
  private projectRoot: string;
  private dotDir: string;
  private sourcemapPath: string;

  constructor(projectRoot: string) {
    this.projectRoot = projectRoot;
    this.dotDir = path.join(projectRoot, '.studiobridge');
    this.sourcemapPath = path.join(this.dotDir, 'sourcemap.json');
  }

  async generate(
    existingFilesState?: Record<string, { className: ScriptClassName }>
  ): Promise<RojoSourcemapNode> {
    const rootNode: RojoSourcemapNode = {
      name: 'DataModel',
      className: 'DataModel',
      children: []
    };

    for (const service of WATCHED_DIRECTORIES) {
      const serviceFullPath = path.join(this.projectRoot, service);
      try {
        const stat = await fs.stat(serviceFullPath);
        if (stat.isDirectory()) {
          const serviceNode: RojoSourcemapNode = {
            name: service,
            className: service,
            filePaths: [service],
            children: []
          };
          await this.buildDirectoryTree(
            serviceFullPath,
            service,
            serviceNode,
            existingFilesState
          );
          rootNode.children!.push(serviceNode);
        }
      } catch {
        // Service directory does not exist on disk, skip
      }
    }

    // Save to .studiobridge/sourcemap.json
    try {
      await fs.mkdir(this.dotDir, { recursive: true });
      await fs.writeFile(
        this.sourcemapPath,
        JSON.stringify(rootNode, null, 2),
        'utf8'
      );
    } catch (err) {
      console.error('Failed to write sourcemap.json:', err);
    }

    return rootNode;
  }

  private async buildDirectoryTree(
    dirFullPath: string,
    dirRelPath: string,
    parentNode: RojoSourcemapNode,
    existingFilesState?: Record<string, { className: ScriptClassName }>
  ): Promise<void> {
    const entries = await fs.readdir(dirFullPath, { withFileTypes: true });

    // Map by base name to handle script + folder pair (Rojo init.lua equivalent)
    const filesByName = new Map<string, string>(); // baseName -> full filename
    const subDirsByName = new Map<string, string>(); // dirName -> full dirName

    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;

      if (entry.isFile() && entry.name.endsWith('.luau')) {
        const baseName = path.basename(entry.name, '.luau');
        filesByName.set(baseName, entry.name);
      } else if (entry.isDirectory()) {
        subDirsByName.set(entry.name, entry.name);
      }
    }

    // Process nodes
    const processedDirNames = new Set<string>();

    for (const [baseName, fileName] of filesByName.entries()) {
      const scriptRelPath = normalizeRelPath(path.join(dirRelPath, fileName));
      const existing = existingFilesState?.[scriptRelPath];
      const className = determineClassName(scriptRelPath, undefined, existing?.className);

      const scriptNode: RojoSourcemapNode = {
        name: baseName,
        className,
        filePaths: [scriptRelPath],
        children: []
      };

      // Check if there is a companion directory with the same name (Example/ + Example.luau)
      if (subDirsByName.has(baseName)) {
        processedDirNames.add(baseName);
        const childDirFullPath = path.join(dirFullPath, baseName);
        const childDirRelPath = path.join(dirRelPath, baseName);
        await this.buildDirectoryTree(
          childDirFullPath,
          childDirRelPath,
          scriptNode,
          existingFilesState
        );
      }

      parentNode.children!.push(scriptNode);
    }

    // Process remaining folders (normal Folder instances)
    for (const [dirName] of subDirsByName.entries()) {
      if (processedDirNames.has(dirName)) continue;

      const folderRelPath = normalizeRelPath(path.join(dirRelPath, dirName));
      const folderNode: RojoSourcemapNode = {
        name: dirName,
        className: 'Folder',
        filePaths: [folderRelPath],
        children: []
      };

      const childDirFullPath = path.join(dirFullPath, dirName);
      await this.buildDirectoryTree(
        childDirFullPath,
        folderRelPath,
        folderNode,
        existingFilesState
      );
      parentNode.children!.push(folderNode);
    }
  }
}
