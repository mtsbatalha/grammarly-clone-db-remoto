# ===========================================
# Grammarly Clone - Restart Docker Containers
# Windows/PowerShell Version
# ===========================================

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
    $projectRoot = Split-Path -Parent $scriptDir
    
    $dockerComposePath = Join-Path $projectRoot "docker-compose.yml"
    
    if (-not (Test-Path $dockerComposePath)) {
        Write-ErrorMessage "Could not find project root. Expected docker-compose.yml at $projectRoot"
        exit 1
    }
    
    return $projectRoot
}

function Main {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  Restarting Docker Containers" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    
    Write-Host "This script will:"
    Write-Host "  1. Stop all running containers"
    Write-Host "  2. Remove stopped containers"
    Write-Host "  3. Start containers again"
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
    $dockerComposeCmd = "docker compose"
    try {
        & docker compose version | Out-Null
    } catch {
        $dockerComposeCmd = "docker-compose"
    }
    
    # Stop containers
    Write-StepMessage "Stopping containers..."
    & $dockerComposeCmd down 2>$null
    Write-SuccessMessage "Containers stopped"
    
    Write-Host ""
    
    # Remove orphan containers
    Write-StepMessage "Cleaning up orphaned containers..."
    & $dockerComposeCmd down --remove-orphans 2>$null
    Write-SuccessMessage "Cleanup complete"
    
    Write-Host ""
    
    # Start containers again
    Write-StepMessage "Starting containers..."
    & $dockerComposeCmd up -d
    Write-SuccessMessage "Containers started"
    
    Write-Host ""
    
    # Wait for services
    Write-StepMessage "Waiting for services to be ready..."
    Start-Sleep -Seconds 3
    
    # Check PostgreSQL
    $postgresContainer = "grammarly_postgres"
    for ($i = 1; $i -le 30; $i++) {
        try {
            $result = & docker exec $postgresContainer pg_isready -U postgres 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMessage "PostgreSQL is ready"
                break
            }
        } catch {
            # Continue
        }
        
        if ($i -lt 30) {
            Write-Host "Waiting for PostgreSQL... ($i/30)"
            Start-Sleep -Seconds 2
        }
    }
    
    # Check Redis
    $redisContainer = "grammarly_redis"
    for ($i = 1; $i -le 30; $i++) {
        try {
            $result = & docker exec $redisContainer redis-cli ping 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMessage "Redis is ready"
                break
            }
        } catch {
            # Continue
        }
        
        if ($i -lt 30) {
            Write-Host "Waiting for Redis... ($i/30)"
            Start-Sleep -Seconds 2
        }
    }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "  All containers restarted successfully!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Services status:"
    & $dockerComposeCmd ps
}

# Run main function
Main
