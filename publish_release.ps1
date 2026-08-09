# watchAny One-Click Release Script
# Auto-builds all 5 release assets (Android 3 ABIs + Windows ZIP + Windows Setup Installer)
# Commits code, creates git tag, and publishes the release with all 5 assets to GitHub.

param(
    [string]$Notes = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$Gh = "C:\Program Files\GitHub CLI\gh.exe"

Set-Location $ProjectRoot

# Stop any running instances of watch_any.exe so files are not locked during compilation
Stop-Process -Name "watch_any" -Force -ErrorAction SilentlyContinue

# 1. Read version from pubspec.yaml
$pubspec = Get-Content "$ProjectRoot\pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*([\d]+\.[\d]+\.[\d]+)\+') {
    $Version = $Matches[1]
} else {
    Write-Error "Could not read version from pubspec.yaml"
    exit 1
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  watchAny One-Click Release Publisher v$Version" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# 2. Sync version in installer.iss
$issPath = "$ProjectRoot\installer.iss"
if (Test-Path $issPath) {
    $issContent = Get-Content $issPath -Raw
    $issContent = $issContent -replace '#define MyAppVersion ".*?"', "#define MyAppVersion ""$Version"""
    Set-Content $issPath -Value $issContent -Encoding UTF8
    Write-Host "  [OK] installer.iss version synced to $Version" -ForegroundColor Green
}

# 3. Clean old release assets
Write-Host "[1/5] Cleaning old build artifacts..." -ForegroundColor Yellow
$oldZip = "$ProjectRoot\watchany_portable_$Version.zip"
if (Test-Path $oldZip) { Remove-Item $oldZip -Force }
$oldSetup = "$ProjectRoot\build\windows\watchany_setup_$Version.exe"
if (Test-Path $oldSetup) { Remove-Item $oldSetup -Force }
flutter clean

# 4. Build Android split-per-abi APKs
Write-Host "[2/5] Building Android APKs (arm64, armeabi-v7a, x86_64)..." -ForegroundColor Yellow
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { Write-Error "Android build failed"; exit 1 }

$ApkSrc = "$ProjectRoot\build\app\outputs\flutter-apk"
$Abis = @("arm64-v8a", "armeabi-v7a", "x86_64")
foreach ($Abi in $Abis) {
    $Src = "$ApkSrc\app-$Abi-release.apk"
    $Dst = "$ProjectRoot\watchany-v$Version-$Abi.apk"
    if (Test-Path $Src) {
        Copy-Item $Src $Dst -Force
        Write-Host "  [OK] watchany-v$Version-$Abi.apk" -ForegroundColor Green
    } else {
        Write-Error "MISSING APK: $Src"
        exit 1
    }
}

# 5. Build Windows Release Binary
Write-Host "[3/5] Building Windows release binary..." -ForegroundColor Yellow
Stop-Process -Name "watch_any" -Force -ErrorAction SilentlyContinue
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Write-Error "Windows build failed"; exit 1 }

$exeFile = Get-ChildItem -Path "$ProjectRoot\build\windows" -Filter "watch_any.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exeFile) {
    $WinRelease = $exeFile.DirectoryName
} else {
    Write-Error "Could not locate compiled watch_any.exe in build\windows"
    exit 1
}
$ZipPath = "$ProjectRoot\watchany_portable_$Version.zip"

# Create Portable ZIP
Write-Host "  Creating portable ZIP..." -ForegroundColor Yellow
tar.exe -a -c -f "$ZipPath" -C "$WinRelease" *
Write-Host "  [OK] watchany_portable_$Version.zip" -ForegroundColor Green

# Build Inno Setup Installer
Write-Host "  Compiling Inno Setup Installer..." -ForegroundColor Yellow
$IsccPaths = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
)
$Iscc = $IsccPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($Iscc) {
    & $Iscc "/DWinReleaseDir=$WinRelease" "$issPath"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Inno Setup compilation failed"
        exit 1
    }
    Write-Host "  [OK] watchany_setup_$Version.exe" -ForegroundColor Green
} else {
    Write-Error "ISCC.exe (Inno Setup) not found!"
    exit 1
}

# 6. Delete old GitHub release if re-publishing
try {
    & $Gh release delete "v$Version" --yes --cleanup-tag 2>&1 | Out-Null
} catch {}
if (git tag -l "v$Version") {
    git tag -d "v$Version"
}

# 7. Commit changes and push git tag
Write-Host "[4/5] Committing git changes and tagging v$Version..." -ForegroundColor Yellow
git add -A
git commit -m "Release v$Version" --allow-empty
git tag -a "v$Version" -m "v$Version" -f
git push origin main --force
git push origin "v$Version" --force

# 8. Create GitHub Release and upload all 5 assets sequentially
Write-Host "[5/5] Publishing v$Version to GitHub with all 5 assets..." -ForegroundColor Yellow

if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = @"
### What's Changed in v$Version
- **Manga Reader End-of-Chapter Performance Fix**: Single-execution completion trigger and RepaintBoundary for bottom chapter card to eliminate scroll choppiness and lag.
- **Automated One-Click Release Pipeline**: Added PowerShell release script `publish_release.ps1` for instant building and publishing of all 5 release assets.
"@
}

Set-Content -Path "$ProjectRoot\release_notes_tmp.txt" -Value $Notes -Encoding UTF8

$zPath = (Get-Item "$ProjectRoot\watchany_portable_$Version.zip").FullName
$sPath = (Get-Item "$ProjectRoot\build\windows\watchany_setup_$Version.exe").FullName
$a1Path = (Get-Item "$ProjectRoot\watchany-v$Version-arm64-v8a.apk").FullName
$a2Path = (Get-Item "$ProjectRoot\watchany-v$Version-armeabi-v7a.apk").FullName
$a3Path = (Get-Item "$ProjectRoot\watchany-v$Version-x86_64.apk").FullName

# Create release with all 5 assets attached atomically
& $Gh release create "v$Version" "$zPath" "$sPath" "$a1Path" "$a2Path" "$a3Path" --title "v$Version" --notes-file "$ProjectRoot\release_notes_tmp.txt"
Remove-Item "$ProjectRoot\release_notes_tmp.txt" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  SUCCESS! Release v$Version published with 5 assets!" -ForegroundColor Green
Write-Host "  https://github.com/Fluffy-The-Penguin/watchAny-2.0/releases/tag/v$Version" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
