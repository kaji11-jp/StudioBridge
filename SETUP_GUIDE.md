# StudioBridge クイック導入ガイド（チームメンバー用）

Node.js や npm などの開発環境は一切不要です。
配布された **`studiobridge.exe`** と **Roblox Studio プラグイン** だけで、3分で利用開始できます。

---

## 1. 事前準備（Roblox Studio側の設定）

チームメンバーのうち誰か1人が、プレイスの設定で HTTP 通信を許可しておきます。
1. Roblox Studio でプレイスを開く
2. **Home（ホーム）** タブ → **Game Settings（ゲーム設定）** を開く
3. **Security（セキュリティ）** を選択
4. **Allow HTTP Requests（HTTPリクエストを許可）** を **ON（有効）** にして保存

---

## 2. プラグインの導入

### 方法：プラグインファイル（.rbxm）を配置する
1. 配布された `StudioBridge.rbxm`（またはプラグイン）を以下のフォルダに配置します。
   - **Windows の場合**：
     エクスプローラーのアドレスバーに以下を貼り付けて Enter を押します。
     ```text
     %LOCALAPPDATA%\Roblox\Plugins
     ```
   - 開いたフォルダに `StudioBridge.rbxm` を置くだけで、Studio のツールバーに **StudioBridge** ボタンが表示されます。

---

## 3. 日常の開発手順（使い方）

### ステップ 1：同期の開始
1. 開発したい作業フォルダ（例: `C:\Projects\MyGame`）を開きます。
2. そのフォルダに `studiobridge.exe` を配置します。
3. ターミナル（PowerShell等）で以下を実行します：
   ```powershell
   .\studiobridge.exe start
   ```
   > 💡 **ヒント**：`studiobridge.exe` をダブルクリックするだけでも自動的にそのフォルダで起動します。

### ステップ 2：Studio と接続
1. Roblox Studio で対象のプレイスを開きます。
2. ツールバーの **StudioBridge** ボタンをクリックしてパネルを開きます。
3. **「Connect」** をクリック（「Status: Connected」になります）。

### ステップ 3：コードの初回吸い出し（Pull）
1. パネルの **「Pull from Studio (Export to Local)」** をクリックします。
2. ローカルフォルダに `ReplicatedStorage` や `ServerScriptService` などの `.luau` ファイルが一括展開されます。

---

## 4. 開発中・同期のルール
- **VS Code 等での保存**：
  ファイルを保存すると、約 0.15 秒で Roblox Studio 側へ自動反映されます。
- **Studio 側での編集**：
  Studio 側でコードを編集・追加・削除すると、約 0.4 秒でローカルの `.luau` ファイルへ自動反映されます。
- **他のメンバーとの同時編集（競合発生時）**：
  同じ行を同時に編集して衝突した場合は、ローカルの編集内容が `ファイル名.conflict-タイムスタンプ.luau` として同階層に安全に保存されます（コードが勝手に消えることはありません）。
