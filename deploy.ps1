#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy the VPN Browser Jumpbox (Windows / PowerShell version of deploy.sh).

.DESCRIPTION
    Validates configuration, starts gluetun + webtop via Docker Compose,
    waits for the VPN tunnel to come up, and prints the desktop URL.

.EXAMPLE
    .\deploy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# ── Helpers ──────────────────────────────────────────────────────────────────
function Abort($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Info($msg)  { Write-Host "  $msg" }

# ── Pre-flight ────────────────────────────────────────────────────────────────
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Abort "Docker not found. Install Docker Desktop for Windows and ensure it is running."
}

try   { docker compose version 2>&1 | Out-Null }
catch { Abort "Docker Compose v2 not found. Ensure Docker Desktop is up to date." }

try   { docker info 2>&1 | Out-Null }
catch { Abort "Docker daemon is not running. Start Docker Desktop and try again." }

# ── .env setup ───────────────────────────────────────────────────────────────
if (-not (Test-Path .env)) {
    if (-not (Test-Path .env.example)) {
        Abort "No .env or .env.example found."
    }
    Copy-Item .env.example .env
    Info "Created .env from template."
    Info "Fill in VPN_PRIVATE_KEY and DESKTOP_PASSWORD, then re-run."
    exit 1
}

# Load .env into script-scope variables (skip blank lines and comments)
$envVars = @{}
Get-Content .env | Where-Object { $_ -match '^\s*([^#\s][^=]*)=(.*)$' } | ForEach-Object {
    $key   = $Matches[1].Trim()
    $value = $Matches[2].Trim()
    $envVars[$key] = $value
    Set-Item -Path "Env:$key" -Value $value
}

# ── Auto-extract private key from wg0.conf if not set ────────────────────────
$vpnKey = $envVars['VPN_PRIVATE_KEY']
if ([string]::IsNullOrWhiteSpace($vpnKey) -or $vpnKey -eq 'your_private_key_here') {
    $wgConf = Join-Path $PSScriptRoot 'wireguard\wg0.conf'
    if (Test-Path $wgConf) {
        $line = Select-String -Path $wgConf -Pattern '^\s*PrivateKey\s*=' | Select-Object -First 1
        if ($line) {
            $extracted = ($line.Line -replace '^.*=\s*', '').Trim()
            if ($extracted) {
                (Get-Content .env) -replace 'VPN_PRIVATE_KEY=.*', "VPN_PRIVATE_KEY=$extracted" |
                    Set-Content .env -Encoding UTF8
                $envVars['VPN_PRIVATE_KEY'] = $extracted
                $Env:VPN_PRIVATE_KEY        = $extracted
                $vpnKey                     = $extracted
                Info "Extracted PrivateKey from wireguard\wg0.conf and saved to .env."
            }
        }
    }
}

# ── Validate ─────────────────────────────────────────────────────────────────
$vpnKey = $envVars['VPN_PRIVATE_KEY']
if ([string]::IsNullOrWhiteSpace($vpnKey) -or $vpnKey -eq 'your_private_key_here') {
    Abort "VPN_PRIVATE_KEY is not set in .env"
}

$desktopPw = $envVars['DESKTOP_PASSWORD']
if ([string]::IsNullOrWhiteSpace($desktopPw) -or $desktopPw -eq 'changeme_to_something_strong') {
    Abort "DESKTOP_PASSWORD is still the placeholder — edit .env first."
}

$provider = if ($envVars.ContainsKey('VPN_PROVIDER')) { $envVars['VPN_PROVIDER'] } else { 'protonvpn' }
if ($provider -notin @('protonvpn', 'mullvad')) {
    Abort "VPN_PROVIDER must be 'protonvpn' or 'mullvad'. Got: $provider"
}

if ($provider -eq 'mullvad') {
    $addr = $envVars['VPN_ADDRESSES']
    if ([string]::IsNullOrWhiteSpace($addr)) {
        Abort "Mullvad requires VPN_ADDRESSES (your internal WireGuard IP, e.g. 10.64.x.x/32)."
    }
}

$de = if ($envVars.ContainsKey('DESKTOP_ENV')) { $envVars['DESKTOP_ENV'] } else { 'xfce' }
if ($de -notin @('xfce', 'mate', 'kde')) {
    Abort "DESKTOP_ENV must be xfce, mate, or kde. Got: $de"
}

$country = if ($envVars.ContainsKey('VPN_COUNTRY')) { $envVars['VPN_COUNTRY'] } else { 'United States' }

# ── Deploy ───────────────────────────────────────────────────────────────────
Write-Host ""
Info "Provider : $provider"
Info "Desktop  : $de"
Info "Country  : $country"
Write-Host ""

Info "Pulling images..."
docker compose pull --quiet

Info "Starting..."
docker compose up -d

Write-Host ""
Info "Waiting for VPN tunnel (~30s)..."

# Poll docker healthcheck (up to 90s)
$deadline = (Get-Date).AddSeconds(90)
$spinner   = '|/-\'
$i         = 0
while ((Get-Date) -lt $deadline) {
    $health = (docker inspect --format '{{.State.Health.Status}}' jumpbox-vpn 2>$null)
    if ($health -eq 'healthy') { break }
    $c = $spinner[$i % $spinner.Length]
    Write-Host "`r  Waiting $c  (status: $health)" -NoNewline
    Start-Sleep -Seconds 3
    $i++
}
Write-Host "`r  VPN container ready.              "

# ── Verify VPN ───────────────────────────────────────────────────────────────
$vpnIp = 'unknown'
try {
    $vpnIp = (docker exec jumpbox-vpn wget -qO- --timeout=5 https://ipinfo.io/ip 2>$null).Trim()
} catch {}

$hostIp = 'unknown'
try {
    $hostIp = (Invoke-RestMethod -Uri 'https://ipinfo.io/ip' -TimeoutSec 5).Trim()
} catch {}

Info "+--------------------------------------+"
Info "|  Host IP  : $hostIp"
Info "|  VPN  IP  : $vpnIp"
Info "+--------------------------------------+"

if ($vpnIp -ne 'unknown' -and $vpnIp -ne $hostIp) {
    Info "VPN active — traffic is tunneled through $provider."
} else {
    Write-Host "  WARNING: VPN may not be connected yet. Check: docker logs jumpbox-vpn" -ForegroundColor Yellow
}

# ── Tailscale URL ─────────────────────────────────────────────────────────────
$tailscaleIp = ''
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
    try { $tailscaleIp = (tailscale ip --4 2>$null).Trim() } catch {}
}

Write-Host ""
Info "Desktop URL : https://localhost:4001"
if ($tailscaleIp) { Info "Tailscale   : https://${tailscaleIp}:4001" }
Info "Password    : $desktopPw"
Write-Host ""
Info "To stop:             .\stop.ps1"
Info "To wipe saved data:  .\stop.ps1 -Volumes"
Write-Host ""
