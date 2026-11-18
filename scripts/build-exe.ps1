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

# Clean intermediate files
Remove-Item $bundleJs, $blobFile -ErrorAction SilentlyContinue

# Copy distribution assets
Write-Host "📂 Copying plugin, installer, and setup guide..." -ForegroundColor Cyan
$pluginSrc = Join-Path $PSScriptRoot "..\plugin\StudioBridge.server.luau"
$installerSrc = Join-Path $PSScriptRoot "..\install.bat"
$guideSrc = Join-Path $PSScriptRoot "..\SETUP_GUIDE.md"

Copy-Item $pluginSrc $distBin -Force
Copy-Item $installerSrc $distBin -Force
Copy-Item $guideSrc $distBin -Force

# Create ZIP archive for easy distribution
Write-Host "🗜️ Creating distribution ZIP (StudioBridge-v2.0-Windows.zip)..." -ForegroundColor Cyan
$zipOutput = Join-Path $distBin "StudioBridge-v2.0-Windows.zip"
if (Test-Path $zipOutput) {
    Remove-Item $zipOutput -Force
}

$filesToZip = @(
    $exeOutput,
    (Join-Path $distBin "StudioBridge.server.luau"),
    (Join-Path $distBin "install.bat"),
    (Join-Path $distBin "SETUP_GUIDE.md")
)

Compress-Archive -Path $filesToZip -DestinationPath $zipOutput -Force

Write-Host "`n🎉 Build & Packaging complete!" -ForegroundColor Green
Write-Host "   Distribution Package : $zipOutput" -ForegroundColor White
Write-Host "   Executable           : $exeOutput" -ForegroundColor White
