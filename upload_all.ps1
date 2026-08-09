$Gh = "C:\Program Files\GitHub CLI\gh.exe"
$files = @(
    "watchany_portable_2.2.24.zip",
    "build\windows\watchany_setup_2.2.24.exe",
    "watchany-v2.2.24-armeabi-v7a.apk",
    "watchany-v2.2.24-x86_64.apk"
)

foreach ($f in $files) {
    Write-Host "Uploading $f..."
    & $Gh release upload v2.2.24 $f --clobber
}
Write-Host "All assets uploaded!"
