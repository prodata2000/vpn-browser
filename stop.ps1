#Requires -Version 5.1
<#
.SYNOPSIS
    Stop the VPN Browser Jumpbox (Windows / PowerShell version of stop.sh).

.PARAMETER Volumes
    Also delete the persistent volumes (webtop desktop data, gluetun state).
    Equivalent to: docker compose down -v

.EXAMPLE
    .\stop.ps1
    .\stop.ps1 -Volumes
#>
param(
    [switch]$Volumes
)

Set-Location $PSScriptRoot

if ($Volumes) {
    docker compose down -v
} else {
    docker compose down
}

Write-Host "Stopped. Run .\deploy.ps1 to start again."
if (-not $Volumes) {
    Write-Host "To also delete saved desktop data: .\stop.ps1 -Volumes"
}
