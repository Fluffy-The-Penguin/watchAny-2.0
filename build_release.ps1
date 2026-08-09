# watchAny Release Build Script
# Version: auto-read from pubspec.yaml
# Builds: Android APKs (3 ABIs) + Windows portable ZIP + Windows setup installer

param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

# Read version from pubspec.yaml
$pubspec = Get-Content "$ProjectRoot\pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*([\d]+\.[\d]+\.[\d]+)\+') {
    $Version = $Matches[1]
} else {
    Write-Error "Could not read version from pubspec.yaml"
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  watchAny Release Builder v$Version" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Set-Location $ProjectRoot

# Step 1: Flutter pub get
Write-Host "[1/4] Running flutter pub get..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Error "flutter pub get failed"; exit 1 }

# Step 2: Android APKs
if (-not $SkipAndroid) {
    Write-Host ""
    Write-Host "[2/4] Building Android APKs..." -ForegroundColor Yellow

    flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { Write-Error "Android build failed"; exit 1 }

    $ApkSrc = "$ProjectRoot\build\app\outputs\flutter-apk"
    $Abis = @("arm64-v8a", "armeabi-v7a", "x86_64")

    foreach ($Abi in $Abis) {
        $Src = "$ApkSrc\app-$Abi-release.apk"
        $Dst = "$ProjectRoot\watchany-v$Version-$Abi.apk"
        if (Test-Path $Src) {
            Copy-Item $Src $Dst -Force
            Write-Host "  OK: $([System.IO.Path]::GetFileName($Dst))" -ForegroundColor Green
        } else {
            Write-Warning "  MISSING APK: $Src"
        }
    }
} else {
    Write-Host "[2/4] Skipping Android build." -ForegroundColor Gray
}

# Step 3: Windows Build
if (-not $SkipWindows) {
    Write-Host ""
    Write-Host "[3/4] Building Windows release..." -ForegroundColor Yellow

    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { Write-Error "Windows build failed"; exit 1 }

    $WinRelease = "$ProjectRoot\build\windows\x64\runner\Release"

    # Portable ZIP
    $PortableZip = "$ProjectRoot\watchany_portable_$Version.zip"
    Write-Host "  Creating portable ZIP..." -ForegroundColor Yellow
    if (Test-Path $PortableZip) { Remove-Item $PortableZip -Force }
    Compress-Archive -Path "$WinRelease\*" -DestinationPath $PortableZip
    Write-Host "  OK: $([System.IO.Path]::GetFileName($PortableZip))" -ForegroundColor Green

    # Inno Setup Installer
    if (-not $SkipInstaller) {
        Write-Host "  Building Inno Setup installer..." -ForegroundColor Yellow

        $IsccPaths = @(
            "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
            "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
            "C:\Program Files\Inno Setup 6\ISCC.exe",
            "C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
        )
        $Iscc = $IsccPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if ($Iscc) {
            & $Iscc "$ProjectRoot\installer.iss"
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  Inno Setup compilation failed"
            } else {
                $SetupExe = "$ProjectRoot\build\windows\watchany_setup_$Version.exe"
                if (Test-Path $SetupExe) {
                    Write-Host "  OK: $([System.IO.Path]::GetFileName($SetupExe))" -ForegroundColor Green
                }
            }
        } else {
            Write-Warning "  Inno Setup (ISCC.exe) not found. Skipping installer."
            Write-Host "  Install from: https://jrsoftware.org/isdl.php" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "[3/4] Skipping Windows build." -ForegroundColor Gray
}

# Done
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Release v$Version build complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Release artifacts:" -ForegroundColor Cyan

$Artifacts = @()
if (-not $SkipAndroid) {
    $Found = Get-ChildItem "$ProjectRoot\watchany-v$Version-*.apk" -ErrorAction SilentlyContinue
    if ($Found) { $Artifacts += $Found }
}
if (-not $SkipWindows) {
    $Found = Get-ChildItem "$ProjectRoot\watchany_portable_$Version.zip" -ErrorAction SilentlyContinue
    if ($Found) { $Artifacts += $Found }
    $Found = Get-ChildItem "$ProjectRoot\build\windows\watchany_setup_$Version.exe" -ErrorAction SilentlyContinue
    if ($Found) { $Artifacts += $Found }
}

foreach ($f in $Artifacts) {
    $SizeMB = [math]::Round($f.Length / 1MB, 1)
    Write-Host "  $($f.Name)  ($SizeMB MB)" -ForegroundColor White
}
Write-Host ""
