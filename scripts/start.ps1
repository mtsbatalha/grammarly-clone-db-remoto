# ===========================================
# Grammarly Clone - Start Script (Windows)
# ===========================================

$ErrorActionPreference = "Stop"

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Banner {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "     Grammarly Clone - Starting..."        -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Test-Docker {
    Write-Step "Checking Docker..."

    try {
        $null = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Docker is not running. Please start Docker Desktop first."
            exit 1
        }
        Write-Success "Docker is running"
    }
    catch {
        Write-Error-Custom "Docker not found. Please install Docker Desktop first."
        exit 1
    }
}

function Start-DockerServices {
    Write-Step "Starting Docker services (PostgreSQL, Redis)..."

    Set-Location $ProjectRoot

    # Start dev services
    docker-compose -f docker-compose.dev.yml up -d

    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to start Docker services"
        exit 1
    }

    Write-Success "Docker services started"
}

function Wait-ForServices {
    Write-Step "Waiting for services to be ready..."

    # Wait for PostgreSQL
    $maxAttempts = 30
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $result = docker exec grammarly_postgres pg_isready -U postgres 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "PostgreSQL is ready"
                break
            }
        }
        catch {}

        if ($i -eq $maxAttempts) {
            Write-Error-Custom "PostgreSQL failed to start"
            exit 1
        }
        Start-Sleep -Seconds 1
    }

    # Wait for Redis
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $result = docker exec grammarly_redis redis-cli ping 2>&1
            if ($result -match "PONG") {
                Write-Success "Redis is ready"
                break
            }
        }
        catch {}

        if ($i -eq $maxAttempts) {
            Write-Error-Custom "Redis failed to start"
            exit 1
        }
        Start-Sleep -Seconds 1
    }
}

function Test-Environment {
    Write-Step "Checking environment configuration..."

    $envFile = Join-Path $ProjectRoot "apps\api\.env"

    if (-not (Test-Path $envFile)) {
        Write-Error-Custom ".env file not found at apps\api\.env"
        Write-Host "Copy from .env.example and configure your settings"
        exit 1
    }

    Write-Success "Environment configured"
}

function Start-Application {
    Write-Step "Starting application..."

    Set-Location $ProjectRoot

    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "  Application Starting!"                     -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Web:  " -NoNewline
    Write-Host "http://localhost:5173" -ForegroundColor Cyan
    Write-Host "  API:  " -NoNewline
    Write-Host "http://localhost:3003" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Press " -NoNewline
    Write-Host "Ctrl+C" -ForegroundColor Yellow -NoNewline
    Write-Host " to stop"
    Write-Host ""

    # Start the dev server
    npm run dev
}

# Main
function Main {
    Write-Banner
    Test-Docker
    Start-DockerServices
    Wait-ForServices
    Test-Environment
    Start-Application
}

Main
