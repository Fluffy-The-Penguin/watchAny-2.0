# WatchAny - Watch Together Self-Hosted Relay Launcher
# Starts the relay server on port 8080 AND exposes it publicly via Cloudflare Tunnel
# Double-click this file OR run: powershell -ExecutionPolicy Bypass -File start_relay.ps1

$node = "C:\Program Files\nodejs\node.exe"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cloudflared = Join-Path $scriptDir "cloudflared.exe"

# Check node
if (-not (Test-Path $node)) {
  Write-Host "[ERROR] Node.js not found at $node. Install from nodejs.org." -ForegroundColor Red
  Read-Host "Press Enter to exit"
  exit 1
}

# Start relay server in background
Write-Host "[*] Starting Watch Together relay server on port 8080..." -ForegroundColor Cyan
$relayJob = Start-Job -ScriptBlock {
  param($n, $d)
  & $n "$d\server.js"
} -ArgumentList $node, $scriptDir

Start-Sleep -Seconds 2

# Health check
try {
  $health = Invoke-WebRequest "http://localhost:8080/health" -UseBasicParsing -TimeoutSec 3
  Write-Host "[OK] Relay server is healthy: $($health.Content)" -ForegroundColor Green
} catch {
  Write-Host "[WARN] Relay health check failed, but continuing..." -ForegroundColor Yellow
}

# Start Cloudflare Tunnel
if (Test-Path $cloudflared) {
  Write-Host "" 
  Write-Host "[*] Starting Cloudflare Tunnel..." -ForegroundColor Cyan
  Write-Host "[*] Copy the 'trycloudflare.com' URL below into WatchAny's relay URL setting." -ForegroundColor Yellow
  Write-Host ""
  # Run cloudflared in foreground so user sees the URL
  & $cloudflared tunnel --url http://localhost:8080 --no-autoupdate
} else {
  Write-Host ""
  Write-Host "[INFO] cloudflared.exe not found. Relay is running locally only (LAN mode)." -ForegroundColor Yellow
  Write-Host "[INFO] For internet access, get cloudflared from: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" -ForegroundColor Gray
  Write-Host ""
  Write-Host "Press Ctrl+C to stop the relay server."
  Wait-Job $relayJob
}
