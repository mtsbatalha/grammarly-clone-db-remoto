# ===========================================
# DANGER: Uninstall / Cleanup Script (PowerShell)
# ===========================================

$ErrorActionPreference = "Stop"

function Print-Red { param($Text) Write-Host $Text -ForegroundColor Red }
function Print-Yellow { param($Text) Write-Host $Text -ForegroundColor Yellow }
function Print-Cyan { param($Text) Write-Host $Text -ForegroundColor Cyan }
function Print-Green { param($Text) Write-Host $Text -ForegroundColor Green }

Print-Red ""
Print-Red "==========================================="
Print-Red "   ⚠️   DANGER ZONE: PROJECT UNINSTALL   ⚠️"
Print-Red "==========================================="
Print-Red ""
Write-Host "This script will completely wipe the project environment."
Write-Host "The following will be DELETED PERMANENTLY:"
Write-Host "  - All Docker containers (API, Redis, Ollama, Web)"
Write-Host "  - All local data volumes (Redis, Ollama)"
Write-Host "  - All Docker images created by this project"
Write-Host "  - All node_modules and build files"
Write-Host ""
Write-Host "NOTE: Remote database (Neon) is NOT affected." -ForegroundColor Cyan
Write-Host ""

# First Confirmation
$confirm1 = Read-Host "Are you sure you want to proceed? (type 'yes' to continue)"
if ($confirm1 -ne "yes") {
    Write-Host "Aborted."
    exit 0
}

# Second Confirmation
Write-Host ""
Print-Red "WARNING: This is your last chance. Data will be lost."
$confirm2 = Read-Host "Are you REALLY sure? (type 'delete-everything' to confirm)"
if ($confirm2 -ne "delete-everything") {
    Write-Host "Aborted."
    exit 0
}

Write-Host ""
Print-Cyan "[*] Starting cleanup..."

# Detect docker compose
$ComposeCmd = "docker compose"
if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    $ComposeCmd = "docker-compose"
}

# 1. Docker Cleanup
Print-Yellow "[1/4] Removing Docker resources..."
Invoke-Expression "$ComposeCmd down -v --rmi all --remove-orphans"
Print-Cyan "Docker resources removed."

# 2. Node Modules Cleanup
Print-Yellow "[2/4] Removing node_modules..."
Get-ChildItem -Path . -Include "node_modules" -Recurse -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Print-Cyan "node_modules removed."

# 3. Artifacts Cleanup
Print-Yellow "[3/4] Removing build artifacts (.turbo, dist, .next)..."
$artifacts = @(".turbo", "dist", "build", ".next", "coverage")
foreach ($art in $artifacts) {
    if (Test-Path $art) {
        Remove-Item $art -Recurse -Force
    }
}
Print-Cyan "Artifacts removed."

# 4. File Deletion (Optional/Manual advice)
Print-Yellow "[4/4] Final Step"
Write-Host ""
Print-Green "The project environment has been wiped."
Write-Host "To completely remove the project files, run this command after exiting:"
Write-Host ""
Print-Red "    Remove-Item -Recurse -Force $(Get-Location)"
Write-Host ""
