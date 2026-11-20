# StudioBridge v2.0

> Roblox Studio 双方向・複数人・AI対応スクリプト同期ツール（TypeScript / Node.js）

---

## 🌟 特徴

1. **ゼロコンフィグ＆途中参加対応**：
   - `default.project.json` などの煩雑な設定ファイルは不要。
   - 既存プロジェクトでも、1人だけがStudioプラグインから「Pull from Studio」を押すだけで即座にローカルへ吸い出し可能。
2. **完全双方向＆ロックフリー（Team Create完全相乗り）**：
   - VS Code / AIエージェントと Roblox Studio 間の相互変更をリアルタイム同期。
   - `ScriptEditorService:UpdateSourceAsync()` による安全なコード書き換え。
3. **拡張子統一（`.luau`）＆階層ベース判定**：
   - すべてのスクリプトは `.luau`。
   - 配置フォルダやマジックコメント（`--!server`, `--!client`, `--!module`）でクラス種別（`Script`, `LocalScript`, `ModuleScript`）を自動決定。
4. **AIエージェントネイティブ**：
   - `.studiobridge/output.log`：Studioのログ（print / warn / error）を直近1,000行ローテーション保存。
   - `.studiobridge/tree.txt`：WorkspaceやReplicatedStorage等の階層マップを属性付きで軽量出力。
5. **データロストゼロの3-wayマージ＆安全退避**：
   - 前回同期ベースキャッシュを用いた3-wayマージ（diff3）。
   - 同一行の重複編集による衝突時は、Studio側を優先しつつローカルの編集内容を `Target.conflict-<タイムスタンプ>.luau` に安全退避。
6. **VS Code 拡張機能ネイティブ（将来拡張対応）**：
   - `@studiobridge/core`：コアロジックを独立ライブラリとして分離。
   - `GET /events`（SSE：Server-Sent Events）：ステータス変化やログ、コンフリクトをUIクライアントへリアルタイム配信。
   - `.studiobridge/sourcemap.json`：`luau-lsp` 等が型補完やパス解決で利用できる Rojo 互換の sourcemap を自動生成。

---

## 🔌 Roblox Studio プラグイン

Roblox Creator Store からワンクリックで Studio に追加できます：
👉 **[StudioBridge - Roblox Creator Store](https://create.roblox.com/store/asset/104187612371514)**

---

## 📁 ディレクトリ構成

```text
rojo-like/
├── packages/
│   ├── core/                  # @studiobridge/core (コアエンジン)
│   │   ├── src/
│   │   │   ├── engine.ts      # BridgeEngine (メインファサード)
│   │   │   ├── server/        # HTTP API + SSE (/events)
│   │   │   ├── state/         # StateManager (状態・キャッシュ管理)
│   │   │   ├── watcher/       # FileWatcher (chokidar 監視・デバウンス)
│   │   │   ├── merge/         # 3-wayマージ (node-diff3)
│   │   │   ├── sourcemap/     # sourcemap.json 自動生成
│   │   │   └── context/       # AI向け output.log / tree.txt
│   │   └── test/              # 統合E2Eテスト
│   └── cli/                   # studiobridge CLI
│       └── src/index.ts       # CLIラッパー
├── plugin/                    # Roblox Studio プラグイン
│   └── src/
│       ├── Main.server.luau   # UI・イベント・ポーリング
│       ├── SyncManager.luau   # 差分適用・ScriptEditorService
│       ├── TreeExporter.luau  # インスタンスツリー抽出
│       └── Config.luau        # 通信設定
└── .studiobridge/             # 自動生成（Git除外推奨）
    ├── output.log             # Studioの最新ログ
    ├── tree.txt               # インスタンス階層
    ├── state.json             # 同期ハッシュ・状態
    ├── sourcemap.json         # Rojo互換 sourcemap
    └── cache/                 # 3-wayマージ用Baseキャッシュ
```

---

## 🚀 クイックスタート

### 1. ビルド & テスト
```bash
npm install
npm run build
npm test
```

### 2. CLI の起動
```bash
npm start
# または
node packages/cli/dist/index.js start --port 34872
```

### 3. コマンド一覧
- `studiobridge start [-p <port>] [-d <dir>]`：サーバーおよびファイル監視を起動
- `studiobridge clear-log`：`.studiobridge/output.log` をクリア
- `studiobridge sourcemap`：`.studiobridge/sourcemap.json` を手動再生成

---

## 🔌 VS Code 拡張機能での利用方法（組み込み例）

```typescript
import { BridgeEngine } from '@studiobridge/core';

const engine = new BridgeEngine({
  projectRoot: vscode.workspace.workspaceFolders[0].uri.fsPath,
  port: 34872
});

await engine.start();

// リアルタイムイベントの受信
engine.on('localChange', event => {
  console.log('Local file changed:', event.path);
});

engine.server.on('conflict', event => {
  vscode.window.showWarningMessage(`Conflict detected in ${event.path}. Saved backup.`);
});
```
