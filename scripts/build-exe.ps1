# StudioBridge Standalone Executable & Distribution Packager
$ErrorActionPreference = "Stop"

Write-Host "📦 Building StudioBridge Core & CLI..." -ForegroundColor Cyan
npm run build

$distBin = Join-Path $PSScriptRoot "..\dist-bin"
if (-not (Test-Path $distBin)) {
    New-Item -ItemType Directory -Path $distBin -Force | Out-Null
}

$bundleJs = Join-Path $distBin "bundle.cjs"
$blobFile = Join-Path $distBin "sea-prep.blob"
$exeOutput = Join-Path $distBin "studiobridge.exe"

Write-Host "⚡ Bundling single JavaScript file with esbuild..." -ForegroundColor Cyan
npx esbuild packages/cli/src/index.ts --bundle --platform=node --target=node20 --outfile=$bundleJs --format=cjs

Write-Host "🔨 Generating SEA preparation blob..." -ForegroundColor Cyan
node --experimental-sea-config sea-config.json

Write-Host "📋 Copying node runtime binary..." -ForegroundColor Cyan
$nodeExe = (Get-Command node).Source
Copy-Item $nodeExe $exeOutput -Force

Write-Host "💉 Injecting SEA blob into studiobridge.exe..." -ForegroundColor Cyan
npx postject $exeOutput NODE_SEA_BLOB $blobFile --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2

# Clean intermediate build files
Remove-Item $bundleJs, $blobFile -ErrorAction SilentlyContinue

# Distribution Staging Folder
$stageDir = Join-Path $distBin "StudioBridge"
if (Test-Path $stageDir) {
    Remove-Item $stageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

Write-Host "📂 Assembling distribution files in $stageDir..." -ForegroundColor Cyan
$pluginSrc = Join-Path $PSScriptRoot "..\plugin\StudioBridge.server.luau"
$installerSrc = Join-Path $PSScriptRoot "..\install.bat"
$guideSrc = Join-Path $PSScriptRoot "..\SETUP_GUIDE.md"

Copy-Item $exeOutput $stageDir -Force
Copy-Item $pluginSrc $stageDir -Force
Copy-Item $installerSrc $stageDir -Force
Copy-Item $guideSrc $stageDir -Force

# Also keep root copies in dist-bin
Copy-Item $pluginSrc $distBin -Force
Copy-Item $installerSrc $distBin -Force
Copy-Item $guideSrc $distBin -Force

# Create ZIP archive containing the StudioBridge folder
Write-Host "🗜️ Creating distribution ZIP (StudioBridge-v2.0-Windows.zip)..." -ForegroundColor Cyan
$zipOutput = Join-Path $distBin "StudioBridge-v2.0-Windows.zip"
if (Test-Path $zipOutput) {
    Remove-Item $zipOutput -Force
}

Compress-Archive -Path "$stageDir\*" -DestinationPath $zipOutput -Force
Remove-Item $stageDir -Recurse -Force

Write-Host "`n🎉 Build & Packaging complete!" -ForegroundColor Green
Write-Host "   Distribution Package : $zipOutput" -ForegroundColor White
Write-Host "   Executable           : $exeOutput" -ForegroundColor White
