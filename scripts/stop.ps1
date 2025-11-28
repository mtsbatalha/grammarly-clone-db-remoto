# ===========================================
# Grammarly Clone - Stop Script (Windows)
# ===========================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host ""
Write-Host "===========================================" -ForegroundColor Blue
Write-Host "     Grammarly Clone - Stopping..."        -ForegroundColor Blue
Write-Host "===========================================" -ForegroundColor Blue
Write-Host ""

Set-Location $ProjectRoot

Write-Host "[*] Stopping Docker services..." -ForegroundColor Green
docker-compose -f docker-compose.dev.yml down

Write-Host ""
Write-Host "[OK] All services stopped" -ForegroundColor Green
Write-Host ""
