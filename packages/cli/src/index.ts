#!/usr/bin/env node

import { Command } from 'commander';
import pc from 'picocolors';
import path from 'node:path';
import fs from 'node:fs/promises';
import { BridgeEngine, ContextManager } from '@studiobridge/core';
import { exec } from 'node:child_process';
import { promisify } from 'node:util';

const execAsync = promisify(exec);

const program = new Command();

program
  .name('studiobridge')
  .description('Roblox Studio bi-directional script sync CLI with AI & Team Create support')
  .version('2.0.0');

function resolveProjectRoot(dirOption?: string): string {
  if (dirOption) {
    return path.resolve(dirOption);
  }
  return process.cwd();
}

program
  .command('start')
  .description('Start the local bridge server and file watcher')
  .option('-p, --port <number>', 'Port for the local HTTP server', '34872')
  .option('-d, --dir <path>', 'Project root directory')
  .action(async options => {
    const projectRoot = resolveProjectRoot(options.dir);
    const port = parseInt(options.port, 10);

    // Ensure watched root folders exist if user starts in empty project
    const defaultDirs = [
      'ReplicatedStorage',
      'ServerScriptService',
      'StarterPlayer/StarterPlayerScripts',
      'StarterPlayer/StarterCharacterScripts'
    ];
    for (const d of defaultDirs) {
      await fs.mkdir(path.join(projectRoot, d), { recursive: true });
    }

    console.log(pc.cyan(pc.bold('\n🌉 StudioBridge v2.0')));
    console.log(pc.gray(`Project root: ${projectRoot}`));
    console.log(pc.gray(`Server address: http://127.0.0.1:${port}`));
    console.log(pc.gray('--------------------------------------------------'));

    const engine = new BridgeEngine({
      projectRoot,
      port
    });

    engine.on('started', info => {
      console.log(pc.green(`✔ Local Bridge Server is running on port ${info.port}`));
      console.log(pc.blue(`ℹ Ready for Roblox Studio plugin connection.\n`));
      console.log(pc.dim(`Endpoints:`));
      console.log(pc.dim(`  - Studio Sync: http://127.0.0.1:${info.port}/health`));
      console.log(pc.dim(`  - Live Events (SSE): http://127.0.0.1:${info.port}/events`));
      console.log(pc.dim(`  - AI Context: .studiobridge/output.log & tree.txt\n`));
    });

    engine.on('localChange', event => {
      const typeBadge = event.type === 'delete' ? pc.red('[DELETE]') : pc.green('[UPSERT]');
      console.log(`${typeBadge} ${pc.white(event.path)} (${event.className || 'Script'})`);
    });

    engine.server.on('error', err => {
      console.error(pc.red(`Server error: ${err.message}`));
    });

    await engine.start();

    // Handle graceful shutdown
    const shutdown = async () => {
      console.log(pc.yellow('\nShutting down StudioBridge...'));
      await engine.stop();
      process.exit(0);
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
  });

program
  .command('clear-log')
  .description('Clear .studiobridge/output.log')
  .option('-d, --dir <path>', 'Project root directory')
  .action(async options => {
    const projectRoot = resolveProjectRoot(options.dir);
    const ctx = new ContextManager(projectRoot);
    await ctx.clearLogs();
    console.log(pc.green('✔ Cleared .studiobridge/output.log'));
  });

program
  .command('sourcemap')
  .description('Generate Rojo-compatible sourcemap.json')
  .option('-d, --dir <path>', 'Project root directory')
  .action(async options => {
    const projectRoot = resolveProjectRoot(options.dir);
    const { SourcemapGenerator } = await import('@studiobridge/core');
    const generator = new SourcemapGenerator(projectRoot);
    const map = await generator.generate();
    console.log(pc.green('✔ Generated .studiobridge/sourcemap.json'));
  });

program
  .command('install')
  .description('Install StudioBridge globally to user PATH and setup Studio plugin')
  .action(async () => {
    console.log(pc.cyan(pc.bold('\n🚀 Installing StudioBridge to system...')));

    const localAppData = process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE || 'C:\\', 'AppData', 'Local');
    const installDir = path.join(localAppData, 'Programs', 'StudioBridge');
    const targetExe = path.join(installDir, 'studiobridge.exe');
    const currentExe = process.execPath;

    await fs.mkdir(installDir, { recursive: true });

    // Copy executable if not already in target
    if (path.resolve(currentExe).toLowerCase() !== path.resolve(targetExe).toLowerCase()) {
      try {
        await fs.copyFile(currentExe, targetExe);
        console.log(pc.green(`✔ Copied executable to: ${targetExe}`));
      } catch (err: any) {
        console.warn(pc.yellow(`⚠️ Could not overwrite target executable: ${err.message}`));
      }
    } else {
      console.log(pc.green(`✔ Executable already at: ${targetExe}`));
    }

    // Add to User PATH via PowerShell using base64 encoding to prevent quoting issues
    try {
      const psScript = `
        $target = '${installDir.replace(/'/g, "''")}';
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User');
        if (-not $userPath) { $userPath = ''; }
        $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $target };
        $newPath = ($parts + $target) -join ';';
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User');
        Write-Output 'UPDATED';
      `;
      const base64Script = Buffer.from(psScript, 'utf16le').toString('base64');
      const { stdout } = await execAsync(`powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${base64Script}`);
      if (stdout.includes('UPDATED')) {
        console.log(pc.green(`✔ Added to user PATH: ${installDir}`));
      } else {
        console.log(pc.green(`✔ PATH already configured: ${installDir}`));
      }
    } catch (err: any) {
      console.warn(pc.yellow(`⚠️ Failed to update PATH automatically: ${err.message}`));
    }

    // Install Roblox Studio Plugin if possible, or print Creator Store link
    const robloxPluginsDir = path.join(localAppData, 'Roblox', 'Plugins');
    let pluginInstalled = false;
    try {
      await fs.mkdir(robloxPluginsDir, { recursive: true });
      const pluginTarget = path.join(robloxPluginsDir, 'StudioBridge.server.luau');
      
      const candidates = [
        path.join(path.dirname(currentExe), 'StudioBridge.server.luau'),
        path.join(path.dirname(currentExe), 'plugin', 'StudioBridge.server.luau'),
        path.join(path.dirname(currentExe), '..', 'plugin', 'StudioBridge.server.luau'),
        path.join(process.cwd(), 'plugin', 'StudioBridge.server.luau')
      ];

      for (const cand of candidates) {
        try {
          await fs.access(cand);
          await fs.copyFile(cand, pluginTarget);
          console.log(pc.green(`✔ Installed Roblox Studio plugin to: ${pluginTarget}`));
          pluginInstalled = true;
          break;
        } catch {
          // Continue searching
        }
      }
    } catch {
      // Ignore if roblox directory is not accessible
    }

    if (!pluginInstalled) {
      console.log(pc.blue(`ℹ Roblox Studio Plugin (Creator Store):`));
      console.log(pc.cyan(`  https://create.roblox.com/store/asset/104187612371514`));
    }

    console.log(pc.bold(pc.green('\n🎉 StudioBridge has been successfully installed!')));
    console.log(pc.white('You can now open any terminal/PowerShell window in any folder and run:'));
    console.log(pc.cyan(pc.bold('   studiobridge start\n')));
  });

// If no command is provided (e.g. double-clicked in Windows Explorer), default to "start"
if (process.argv.length <= 2) {
  process.argv.push('start');
}

program.parse();
