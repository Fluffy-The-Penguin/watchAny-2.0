$Gh = "C:\Program Files\GitHub CLI\gh.exe"

Write-Host "Deleting old tag/release if exists..."
& $Gh release delete v2.2.25 --yes --cleanup-tag 2>$null | Out-Null
Start-Sleep -Seconds 2

$notes = @"
### What's Changed in v2.2.25
- **Fixed Desktop Extension Update**: Direct APK download and multipart upload to Suwayomi Server ensures manga extensions update cleanly to the latest version and clear from "Updates Available".
- **Automated One-Click Release Pipeline**: Added one-click PowerShell release script `publish_release.ps1` for instant building and asset publishing.
"@
Set-Content -Path "release_notes_tmp.txt" -Value $notes -Encoding UTF8

Write-Host "Creating release v2.2.25 with all 5 assets..."
& $Gh release create v2.2.25 `
  "watchany_portable_2.2.25.zip" `
  "build\windows\watchany_setup_2.2.25.exe" `
  "watchany-v2.2.25-arm64-v8a.apk" `
  "watchany-v2.2.25-armeabi-v7a.apk" `
  "watchany-v2.2.25-x86_64.apk" `
  --title "v2.2.25" `
  --notes-file "release_notes_tmp.txt"

Remove-Item "release_notes_tmp.txt" -Force -ErrorAction SilentlyContinue
Write-Host "Done!"
