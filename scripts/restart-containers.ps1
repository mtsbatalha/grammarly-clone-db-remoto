# ===========================================
# Grammarly Clone - Restart Docker Containers
# Windows/PowerShell Version
# ===========================================
#
# Usage:
#   .\restart-containers.ps1         # Restart main services only
#   .\restart-containers.ps1 -All    # Restart all services including NGINX Proxy Manager
#   .\restart-containers.ps1 -Npm    # Restart NGINX Proxy Manager only
#

param(
    [switch]$All,
    [switch]$Npm
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
    } catch {}

    try {
        $null = docker-compose version 2>$null
        if ($LASTEXITCODE -eq 0) {
            return "docker-compose"
        }
    } catch {}

    Write-ErrorMessage "Docker Compose not found"
    exit 1
}

function Restart-NginxProxyManager {
    param([string]$DockerCompose, [string]$ProjectRoot)

    Write-StepMessage "Stopping NGINX Proxy Manager..."
    if ($DockerCompose -eq "docker compose") {
        docker compose -f docker-compose.npm.yml down 2>$null
    } else {
        docker-compose -f docker-compose.npm.yml down 2>$null
    }

    Write-StepMessage "Starting NGINX Proxy Manager..."
    if ($DockerCompose -eq "docker compose") {
        docker compose -f docker-compose.npm.yml up -d
    } else {
        docker-compose -f docker-compose.npm.yml up -d
    }

    Write-StepMessage "Waiting for NGINX Proxy Manager..."
    for ($i = 1; $i -le 30; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:81" -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-SuccessMessage "NGINX Proxy Manager is ready"
                return
            }
        } catch {
            # Continue waiting
        }
        Write-Host "Waiting for NPM... ($i/30)"
        Start-Sleep -Seconds 2
    }
}

function Restart-MainServices {
    param([string]$DockerCompose, [string]$ProjectRoot)

    # Stop containers
    Write-StepMessage "Stopping main containers..."
    if ($DockerCompose -eq "docker compose") {
        docker compose down 2>$null
    } else {
        docker-compose down 2>$null
    }
    Write-SuccessMessage "Containers stopped"

    Write-Host ""

    # Remove orphan containers
    Write-StepMessage "Cleaning up orphaned containers..."
    if ($DockerCompose -eq "docker compose") {
        docker compose down --remove-orphans 2>$null
    } else {
        docker-compose down --remove-orphans 2>$null
    }
    Write-SuccessMessage "Cleanup complete"

    Write-Host ""

    # Start containers again
    Write-StepMessage "Starting containers..."
    if ($DockerCompose -eq "docker compose") {
        docker compose up -d
    } else {
        docker-compose up -d
    }
    Write-SuccessMessage "Containers started"

    Write-Host ""

    # Wait for services
    Write-StepMessage "Waiting for services to be ready..."
    Start-Sleep -Seconds 3

    # Check PostgreSQL
    $postgresContainer = "grammarly_postgres"
    for ($i = 1; $i -le 30; $i++) {
        try {
            $null = docker exec $postgresContainer pg_isready -U postgres 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMessage "PostgreSQL is ready"
                break
            }
        } catch {}

        if ($i -lt 30) {
            Write-Host "Waiting for PostgreSQL... ($i/30)"
            Start-Sleep -Seconds 2
        }
    }

    # Check Redis
    $redisContainer = "grammarly_redis"
    for ($i = 1; $i -le 30; $i++) {
        try {
            $null = docker exec $redisContainer redis-cli ping 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMessage "Redis is ready"
                break
            }
        } catch {}

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

    if ($Npm) {
        Write-Host "Mode: NGINX Proxy Manager only"
    } elseif ($All) {
        Write-Host "Mode: All services (including NGINX Proxy Manager)"
    } else {
        Write-Host "Mode: Main services only"
        Write-Host "  Use -All to include NGINX Proxy Manager"
        Write-Host "  Use -Npm to restart only NGINX Proxy Manager"
    }

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

    # Restart based on mode
    if ($Npm) {
        Restart-NginxProxyManager -DockerCompose $dockerCompose -ProjectRoot $projectRoot
    } elseif ($All) {
        Restart-MainServices -DockerCompose $dockerCompose -ProjectRoot $projectRoot
        Write-Host ""
        Restart-NginxProxyManager -DockerCompose $dockerCompose -ProjectRoot $projectRoot
    } else {
        Restart-MainServices -DockerCompose $dockerCompose -ProjectRoot $projectRoot
    }

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
