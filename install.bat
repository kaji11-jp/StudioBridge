@echo off
chcp 65001 >nul
echo ========================================================
echo   StudioBridge Windows インストーラー
echo ========================================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\StudioBridge"
set "ROBLOX_PLUGINS=%LOCALAPPDATA%\Roblox\Plugins"

echo [1/3] プログラムフォルダを作成・配置中...
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%~dp0studiobridge.exe" "%INSTALL_DIR%\studiobridge.exe" >nul
echo      ✔ %INSTALL_DIR%\studiobridge.exe に配置完了

echo [2/3] ユーザー環境変数 PATH を登録中...
rem Base64 encoded PowerShell script to avoid cmd quoting issues
powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand JABkAGkAcgAgAD0AIABbAFMAeQBzAHQAZQBtAC4ASQBPAC4AUABhAHQAaABdADoAOgBDAG8AbQBiAGkAbgBlACgAJABlAG4AdgA6AEwATwBDAEEATABBAFAAUABEAEEAVABBACwAIAAnAFAAcgBvAGcAcgBhAG0AcwAnACwAIAAnAFMAdAB1AGQAaQBvAEIAcgBpAGQAZwBlACcAKQAKACQAbwBsAGQAUABhAHQAaAAgAD0AIABbAEUAbgB2AGkAcgBvAG4AbQBlAG4AdABdADoAOgBHAGUAdABFAG4AdgBpAHIAbwBuAG0AZQBuAHQAVgBhAHIAaQBhAGIAbABlACgAJwBQAGEAdABoACcALAAgACcAVQBzAGUAcgAnACkACgBpAGYAIAAoAC0AbgBvAHQAIAAkAG8AbABkAFAAYQB0AGgAKQAgAHsAIAAkAG8AbABkAFAAYQB0AGgAIAA9ACAAJwAnACAAfQAKACQAcABhAHIAdABzACAAPQAgACQAbwBsAGQAUABhAHQAaAAgAC0AcwBwAGwAaQB0ACAAJwA7ACcAIAB8ACAAVwBoAGUAcgBlAC0ATwBiAGoAZQBjAHQAIAB7ACAAJABfACAALQBhAG4AZAAgACQAXwAgAC0AbgBlACAAJABkAGkAcgAgAH0ACgAkAG4AZQB3AFAAYQB0AGgAIAA9ACAAKAAkAHAAYQByAHQAcwAgACsAIAAkAGQAaQByACkAIAAtAGoAbwBpAG4AIAAnADsAJwAKAFsARQBuAHYAaQByAG8AbgBtAGUAbgB0AF0AOgA6AFMAZQB0AEUAbgB2AGkAcgBvAG4AbQBlAG4AdABWAGEAcgBpAGEAYgBsAGUAKAAnAFAAYQB0AGgAJwAsACAAJABuAGUAdwBQAGEAdABoACwAIAAnAFUAcwBlAHIAJwApAAoAVwByAGkAdABlAC0ASABvAHMAdAAgACcAUABBAFQASABfAFMAVQBDAEMARQBTAFMAJwA= >nul
echo      ✔ ユーザー PATH に登録完了

echo [3/3] Roblox Studio プラグインを確認中...
if exist "%~dp0StudioBridge.server.luau" (
    if not exist "%ROBLOX_PLUGINS%" mkdir "%ROBLOX_PLUGINS%"
    copy /Y "%~dp0StudioBridge.server.luau" "%ROBLOX_PLUGINS%\StudioBridge.server.luau" >nul
    echo      ✔ ローカルプラグインフォルダに配置完了
) else (
    echo      ℹ Creator Store から公式プラグインをインストールしてください:
    echo        https://create.roblox.com/store/asset/104187612371514
)

echo.
echo ========================================================
echo   🎉 インストールが完了しました！
echo ========================================================
echo.
echo 使い方：
echo   1. ターミナル（PowerShell / VS Code）を「新しく」開く
echo   2. 作業したいプロジェクトフォルダへ移動
echo   3. 以下のコマンドを実行するだけでいつでも同期開始！
echo.
echo      studiobridge start
echo.
echo ※ プラグインのインストール（まだの方）:
echo   https://create.roblox.com/store/asset/104187612371514
echo.
pause
