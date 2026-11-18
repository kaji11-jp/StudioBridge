@echo off
chcp 65001 >nul
echo ========================================================
echo   StudioBridge 自動インストーラー
echo ========================================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\StudioBridge"
set "ROBLOX_PLUGINS=%LOCALAPPDATA%\Roblox\Plugins"

echo [1/3] プログラムフォルダを作成中...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%~dp0studiobridge.exe" "%INSTALL_DIR%\studiobridge.exe" >nul
echo      ✔ %INSTALL_DIR%\studiobridge.exe に配置完了

echo [2/3] ユーザー環境変数 PATH を登録中...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dir = '%INSTALL_DIR%';" ^
  "$p = [Environment]::GetEnvironmentVariable('Path', 'User');" ^
  "if ($p -split ';' -notcontains $dir) {" ^
  "    [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ';' + $dir), 'User');" ^
  "    Write-Host '     ✔ PATH に登録しました';" ^
  "} else {" ^
  "    Write-Host '     ✔ すでに PATH に登録済みです';" ^
  "}"

echo [3/3] Roblox Studio プラグインをインストール中...
if not exist "%ROBLOX_PLUGINS%" mkdir "%ROBLOX_PLUGINS%"
if exist "%~dp0StudioBridge.server.luau" (
    copy /Y "%~dp0StudioBridge.server.luau" "%ROBLOX_PLUGINS%\StudioBridge.server.luau" >nul
    echo      ✔ %ROBLOX_PLUGINS%\StudioBridge.server.luau に配置完了
)

echo.
echo ========================================================
echo   🎉 インストールが完了しました！
echo ========================================================
echo.
echo 使い方：
echo   1. ターミナル（PowerShell / コマンドプロンプト）を開き直す
echo   2. 作業したいフォルダへ移動（例: cd C:\MyGame）
echo   3. 以下のコマンドを実行するだけでいつでも同期開始！
echo.
echo      studiobridge start
echo.
pause
