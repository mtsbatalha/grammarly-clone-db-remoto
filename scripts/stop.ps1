# ===========================================
# Grammarly Clone - Stop Script (Windows)
# ===========================================
#
# Usage:
#   .\stop.ps1              # Stop all services
#   .\stop.ps1 -Clean       # Stop and remove port override file
# ===========================================

param(
    [switch]$Clean
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "===========================================" -ForegroundColor Blue
Write-Host "     Grammarly Clone - Stopping..."        -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue
Write-Host ""

Set-Location $ProjectRoot

Write-Host "[*] Stopping Docker services..." -ForegroundColor Green

# Stop with override if it exists
$overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
if (Test-Path $overrideFile) {
    docker-compose -f docker-compose.dev.yml -f docker-compose.override.yml down
}
else {
    docker-compose -f docker-compose.dev.yml down
}

# Clean override file if requested
if ($Clean -and (Test-Path $overrideFile)) {
    Write-Host "[*] Removing port override file..." -ForegroundColor Green
    Remove-Item $overrideFile -Force
    Write-Host "[OK] Override file removed" -ForegroundColor Green
    Write-Host "[NOTE] Default ports will be used on next start" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[OK] All services stopped" -ForegroundColor Green
Write-Host ""
