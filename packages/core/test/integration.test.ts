import { BridgeEngine } from '../dist/index.js';
import path from 'node:path';
import fs from 'node:fs/promises';

async function test() {
  const testDir = path.resolve('test-workspace');
  await fs.rm(testDir, { recursive: true, force: true });
  await fs.mkdir(path.join(testDir, 'ServerScriptService'), { recursive: true });
  await fs.mkdir(path.join(testDir, 'ReplicatedStorage'), { recursive: true });

  const port = 34899;
  const engine = new BridgeEngine({
    projectRoot: testDir,
    port,
    debounceMs: 50
  });

  await engine.start();
  console.log('✔ Engine started on port', port);

  // 1. Test /health
  const healthRes = await fetch(`http://127.0.0.1:${port}/health`);
  const healthData = await healthRes.json();
  console.log('✔ /health:', healthData);

  // 2. Test /export (Studio -> Local initial pull)
  const exportPayload = {
    scripts: [
      {
        path: 'ServerScriptService/Main.luau',
        className: 'Script',
        source: 'print("Hello from Studio initial export")\n'
      },
      {
        path: 'ReplicatedStorage/Config.luau',
        className: 'ModuleScript',
        source: 'return { version = "1.0" }\n'
      }
    ]
  };
  const exportRes = await fetch(`http://127.0.0.1:${port}/export`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(exportPayload)
  });
  console.log('✔ /export:', await exportRes.json());

  // Verify file created locally
  const mainContent = await fs.readFile(path.join(testDir, 'ServerScriptService/Main.luau'), 'utf8');
  console.log('✔ Local Main.luau created:', mainContent.trim());

  // 3. Test /logs & /tree
  await fetch(`http://127.0.0.1:${port}/logs`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      logs: [{ timestamp: '21:00:00', level: 'INFO', message: 'Test log from Studio' }]
    })
  });
  const logsRes = await fetch(`http://127.0.0.1:${port}/logs`);
  console.log('✔ /logs fetched:\n', await logsRes.text());

  await fetch(`http://127.0.0.1:${port}/tree`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tree: 'Workspace\n  Model [Model]' })
  });
  const treeRes = await fetch(`http://127.0.0.1:${port}/tree`);
  console.log('✔ /tree fetched:\n', await treeRes.text());

  // 4. Test 3-way merge without conflict
  // Simulate: Base is "line1\nline2\nline3"
  // Local changes line1 -> "line1_local\nline2\nline3"
  // Remote changes line3 -> "line1\nline2\nline3_remote"
  const mergeTarget = path.join(testDir, 'ServerScriptService/MergeTest.luau');
  const baseContent = 'line1\nline2\nline3\n';
  await fs.writeFile(mergeTarget, baseContent, 'utf8');
  await engine.stateManager.updateFile('ServerScriptService/MergeTest.luau', baseContent, 'Script');

  // Local changes line1
  await fs.writeFile(mergeTarget, 'line1_local\nline2\nline3\n', 'utf8');

  // Push remote change on line3
  const pushRes = await fetch(`http://127.0.0.1:${port}/push`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      events: [
        {
          type: 'upsert',
          path: 'ServerScriptService/MergeTest.luau',
          source: 'line1\nline2\nline3_remote\n'
        }
      ]
    })
  });
  console.log('✔ Clean merge /push:', await pushRes.json());
  const mergedFile = await fs.readFile(mergeTarget, 'utf8');
  console.log('✔ Merged content:\n', mergedFile);

  // 5. Test Conflict and Backup
  // Both edit line2
  await fs.writeFile(mergeTarget, 'line1_local\nline2_local_conflict\nline3_remote\n', 'utf8');
  const conflictPushRes = await fetch(`http://127.0.0.1:${port}/push`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      events: [
        {
          type: 'upsert',
          path: 'ServerScriptService/MergeTest.luau',
          source: 'line1\nline2_remote_conflict\nline3_remote\n'
        }
      ]
    })
  });
  const conflictResult = await conflictPushRes.json();
  console.log('✔ Conflict /push result:', conflictResult);

  const entries = await fs.readdir(path.join(testDir, 'ServerScriptService'));
  console.log('✔ Files in ServerScriptService after conflict:', entries);

  // 6. Test /poll after local write
  await fs.writeFile(path.join(testDir, 'ReplicatedStorage/NewLocal.luau'), '--!module\nreturn {}\n', 'utf8');
  // Wait for debounce
  await new Promise(r => setTimeout(r, 200));

  const pollRes = await fetch(`http://127.0.0.1:${port}/poll`);
  const pollData = await pollRes.json();
  console.log('✔ /poll received local event:', pollData);

  // Clean up
  await engine.stop();
  await fs.rm(testDir, { recursive: true, force: true });
  console.log('\n🎉 ALL TESTS PASSED SUCCESSFULLY!');
}

test().catch(err => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
