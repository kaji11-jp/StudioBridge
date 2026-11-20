# StudioBridge 導入・利用ガイド

> **Node.js や npm などの開発環境は一切不要です。**
> 配布された ZIP パッケージと Roblox Studio だけで、3分で利用開始できます。

---

## 1. プラグインのインストール（Roblox Studio 側）

以下の **いずれか1つの方法** でプラグインを導入してください。

### 方法 A（推奨）：Roblox Creator Store からワンクリック追加
ブラウザで以下の公式ストアリンクを開き、**「Install in Studio」** をクリックするだけで完了です。
👉 **[StudioBridge - Roblox Creator Store](https://create.roblox.com/store/asset/104187612371514)**

### 方法 B（オフライン / 手動）：ファイルを配置する
ZIP 同梱の `install.bat` を実行するか、または `StudioBridge.server.luau` を以下のフォルダに配置するだけで Studio に自動認識されます。
- 配置先フォルダ（エクスプローラーのアドレスバーに貼り付けて Enter）：
  ```text
  %LOCALAPPDATA%\Roblox\Plugins
  ```

---

## 2. Studio のセキュリティ設定（初回のみ）

Roblox Studio のプレイスでローカル通信を許可します。
1. Roblox Studio で対象のプレイスを開く
2. **Home（ホーム）** タブ → **Game Settings（ゲーム設定）** を開く
3. **Security（セキュリティ）** を選択
4. **Allow HTTP Requests（HTTPリクエストを許可）** を **ON（有効）** にして保存

---

## 3. CLI のインストール（Windows 側）

1. 配布された `StudioBridge-v2.0-Windows.zip` を適当なフォルダ（ダウンロード等）に解凍します。
2. 解凍したフォルダ内にある **`install.bat`** をダブルクリックします。
   - `studiobridge.exe` がシステム（`%LOCALAPPDATA%\Programs\StudioBridge`）に自動配置されます。
   - ユーザー環境変数 `PATH` に自動登録されます。
3. **完了！** これ以降は PC 上のどのフォルダからでも `studiobridge` コマンドが使えます。

---

## 4. 日常の開発フロー（超シンプル 3ステップ）

### ステップ 1：作業フォルダで同期サーバーを起動
ターミナル（PowerShell / コマンドプロンプト / VS Codeのターミナル）を開き、開発したいフォルダへ移動して実行します：
```powershell
studiobridge start
```

### ステップ 2：Studio で「Connect」
Roblox Studio 側のツールバーにある **StudioBridge** ボタンを押し、**「Connect」** をクリックします（Status が Green の Connected になります）。

### ステップ 3：コードをローカルへ吸い出し（初回のみ）
プラグインパネルの **「Pull from Studio (Export to Local)」** をクリックします。
Studio 内のスクリプトがローカルの作業フォルダへ一瞬で書き出され、以降は双方向のリアルタイム同期が自動で行われます。

---

## 5. StudioBridge のルール & Rojo との違い（重要 Q&A）

### Q1. StarterPlayerScripts や StarterCharacterScripts は同期できる？
**A. 完全に同期できます！**
Rojo のようにプロジェクト直下に `StarterPlayerScripts/` フォルダを剥き出しで置くのではなく、Roblox の DataModel（Explorer）と完全に一致する **`StarterPlayer/`** 配下に配置する仕様です：
```text
project-root/
└── StarterPlayer/
    ├── StarterPlayerScripts/
    │   └── InputHandler.luau   # LocalScript として自動同期
    └── StarterCharacterScripts/
        └── Movement.luau       # LocalScript として自動同期
```
Studio 側で「Pull from Studio」を実行すれば、自動的にこの正しい階層でローカルに展開されます。

---

### Q2. ServerScriptService 内のモジュールはどうやって ModuleScript にする？
**A. 親フォルダを `Modules`（または `Libs`）にするか、1行目にマジックコメントを書くだけです！**
`.meta.json` などの煩雑な設定ファイルは一切不要です。

- **方法 1（フォルダで分類）**：
  フォルダ名を `Modules` または `Libs` にすると、その配下のスクリプトはすべて `ModuleScript` になります。
  ```text
  ServerScriptService/
  └── Modules/
      └── DamageCalc.luau   # 自動的に ModuleScript になる
  ```
- **方法 2（マジックコメントで明示指定）**：
  ファイルの 1 行目にコメントを書くことで、どのフォルダにあっても種別を 100% 確実に指定できます。
  - `--!server` → `Script`
  - `--!client` → `LocalScript`
  - `--!module` → `ModuleScript`

---

### Q3. default.project.json や .server.luau / .client.luau 拡張子は使えないの？
**A. 使えません（意図的なゼロコンフィグ設計です）。**
StudioBridge は、Rojo が抱える「設定ファイル地獄」「Team Create での排他ロック競合」「拡張子ルールによるツールの分断」を解消するために作られました。
- すべてのスクリプトは **`.luau` に統一** されます。
- `default.project.json` や `.meta.json` などの設定ファイルを全廃したため、開発途中のプロジェクトでも誰か 1 人が「Pull from Studio」を押すだけで即座に全員が開発に参加できます。

---

### Q4. スクリプトの中にスクリプトを入れる構造（init.meta.json 等）はできる？
**A. サポートしていません（非推奨です）。**
Roblox Studio 上で「スクリプトインスタンスの直下に子スクリプトを生やす」ネスト構造は、Team Create における排他ロックの競合多発や、AI エージェントによる自律コード探索を著しく阻害するアンチパターンです。
StudioBridge では、スクリプトとフォルダを明確に分離したクリーンな階層設計を前提としています。
