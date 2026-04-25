# Builds a portable ZIP of the Windows desktop app (run on Windows only).
# Usage (PowerShell, from project root):
#   flutter build windows --release
#   .\tool\package_windows_release.ps1
#
# Output: dist\naboo.exe.zip
# Copy that ZIP to your site: naboo/downloads/windows/

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -notmatch 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
  Write-Error "Could not read version from pubspec.yaml"
  exit 1
}
$releaseDir = Join-Path $root "build\windows\x64\runner\Release"

if (-not (Test-Path $releaseDir)) {
  Write-Error "Missing folder: $releaseDir`nRun first: flutter build windows --release"
  exit 1
}

$exe = Join-Path $releaseDir "naboo.exe"
if (-not (Test-Path $exe)) {
  $exe = Join-Path $releaseDir "basra_store_manager.exe"
}
if (-not (Test-Path $exe)) {
  Write-Warning "Expected naboo.exe or basra_store_manager.exe not found; zipping Release folder anyway."
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zipName = "naboo.exe.zip"
$zipPath = Join-Path $dist $zipName

if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}

Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force
Write-Host "OK: $zipPath"
Write-Host "Upload this file to: naboo/downloads/windows/ and update script.js appLinks.windows"
