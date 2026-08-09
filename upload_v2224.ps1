$Gh = "C:\Program Files\GitHub CLI\gh.exe"

# 1. Cleanup old release/tag if exists
& $Gh release delete v2.2.24 --yes --cleanup-tag 2>$null | Out-Null
Start-Sleep -Seconds 2

# 2. Write notes to temporary file
$notes = @"
### What's Changed in v2.2.24
- **Fixed Desktop Extension Update**: Fixed Desktop Suwayomi manga extension update bug where GraphQL mutation patch parameter was empty, causing updates to stay stuck in 'Updates Available'. Corrected mutation patch to { install: true } and added fallback to direct APK re-installation if repository index hasn't refreshed.
- **Extension Repositories Section**: Added community extension & addon repository lists with direct links to Hayase Repo (Anime), Keiyoushi GitHub (Manga), and Stremio Addons Directory (Movies & Series).
- **Documentation Refinements**: Updated website and wiki documentation to use clean, user-friendly feature descriptions.
"@
Set-Content -Path "release_notes_tmp.txt" -Value $notes -Encoding UTF8

Write-Host "Creating GitHub Release v2.2.24 with all 5 assets..."
& $Gh release create v2.2.24 `
  "watchany_portable_2.2.24.zip#Windows Portable ZIP" `
  "build\windows\watchany_setup_2.2.24.exe#Windows Setup Installer" `
  "watchany-v2.2.24-arm64-v8a.apk#Android ARM64 APK" `
  "watchany-v2.2.24-armeabi-v7a.apk#Android ARM32 APK" `
  "watchany-v2.2.24-x86_64.apk#Android x86_64 APK" `
  --title "v2.2.24" `
  --notes-file "release_notes_tmp.txt"

Remove-Item "release_notes_tmp.txt" -Force -ErrorAction SilentlyContinue
Write-Host "Done!"
