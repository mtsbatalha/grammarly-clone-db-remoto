# ===========================================
# Grammarly Clone - Restart Docker Containers
# Windows/PowerShell Version
# ===========================================
#
# Usage:
#   .\restart-containers.ps1           # Restart all services
#   .\restart-containers.ps1 -ResetPorts   # Reset to default ports
#

param(
    [switch]$ResetPorts
)

# Colors and output functions
function Write-StepMessage {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Get-ProjectRoot {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    if (-not $scriptDir) {
        $scriptDir = $PSScriptRoot
    }
    if (-not $scriptDir) {
        $scriptDir = Get-Location
    }

    $projectRoot = Split-Path -Parent $scriptDir

    $dockerComposePath = Join-Path $projectRoot "docker-compose.yml"

    if (-not (Test-Path $dockerComposePath)) {
        Write-ErrorMessage "Could not find project root. Expected docker-compose.yml at $projectRoot"
        exit 1
    }

    return $projectRoot
}

function Get-DockerComposeCmd {
    try {
        $null = docker compose version 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "docker compose"
        }
    }
    catch {}

    try {
        $null = docker-compose version 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "docker-compose"
        }
    }
    catch {}

    Write-ErrorMessage "Docker Compose not found"
    exit 1
}


function Restart-MainServices {
    param([string]$DockerCompose, [string]$ProjectRoot)

    # Check for override file
    $overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
    $overrideArgs = @()
    
    if (Test-Path $overrideFile) {
        $overrideArgs = @("-f", "docker-compose.override.yml")
        Write-StepMessage "Using port override configuration"
    }

    # Reset ports if requested
    if ($ResetPorts -and (Test-Path $overrideFile)) {
        Write-StepMessage "Removing port override file..."
        Remove-Item $overrideFile -Force
        $overrideArgs = @()
        Write-SuccessMessage "Ports reset to defaults"
    }

    # Stop containers
    Write-StepMessage "Stopping main containers..."
    if ($DockerCompose -eq "docker compose") {
        & docker compose @overrideArgs down 2>$null
    }
    else {
        & docker-compose @overrideArgs down 2>$null
    }
    Write-SuccessMessage "Containers stopped"

    Write-Host ""

    # Remove orphan containers
    Write-StepMessage "Cleaning up orphaned containers..."
    if ($DockerCompose -eq "docker compose") {
        & docker compose @overrideArgs down --remove-orphans 2>$null
    }
    else {
        & docker-compose @overrideArgs down --remove-orphans 2>$null
    }
    Write-SuccessMessage "Cleanup complete"

    Write-Host ""

    # Start containers again
    Write-StepMessage "Starting containers..."
    if ($DockerCompose -eq "docker compose") {
        & docker compose @overrideArgs up -d
    }
    else {
        & docker-compose @overrideArgs up -d
    }
    Write-SuccessMessage "Containers started"

    Write-Host ""

    # Wait for services
    Write-StepMessage "Waiting for services to be ready..."
    Start-Sleep -Seconds 3

    # Check Redis
    $redisContainer = "grammarly_redis"
    for ($i = 1; $i -le 30; $i++) {
        try {
            $null = docker exec $redisContainer redis-cli ping 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMessage "Redis is ready"
                break
            }
        }
        catch {}

        if ($i -lt 30) {
            Write-Host "Waiting for Redis... ($i/30)"
            Start-Sleep -Seconds 2
        }
    }
}

function Main {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  Restarting Docker Containers" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""

    Write-Host "Mode: All services"
    Write-Host "  Use -ResetPorts to reset to default ports"

    Write-Host ""

    $response = Read-Host "Continue? (y/N)"

    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Cancelled."
        exit 0
    }

    Write-Host ""

    # Get project root
    $projectRoot = Get-ProjectRoot
    Set-Location $projectRoot

    # Determine docker compose command
    $dockerCompose = Get-DockerComposeCmd
    Write-StepMessage "Using: $dockerCompose"

    # Restart services
    Restart-MainServices -DockerCompose $dockerCompose -ProjectRoot $projectRoot

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "  All containers restarted successfully!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""

    Write-Host "Services status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Run main function
Main
