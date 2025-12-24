# ===========================================
# Grammarly Clone - Start Script (Windows)
# ===========================================
#
# Features:
#   - Automatic port conflict detection
#   - Port fallback system
#   - Environment variable support
#
# Usage:
#   .\start.ps1              # Normal start with port checking
#   .\start.ps1 -Auto        # Automatic mode (use fallback ports)
#   .\start.ps1 -Help        # Show help
# ===========================================

param(
    [switch]$Auto,
    [switch]$Help,
    [int]$PostgresPort = 0,
    [int]$RedisPort = 0,
    [int]$ApiPort = 0,
    [int]$WebPort = 0
)

$ErrorActionPreference = "Stop"

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# ===========================================
# Default Port Configuration
# ===========================================
$script:DEFAULT_POSTGRES_PORT = 5434
$script:DEFAULT_REDIS_PORT = 6381
$script:DEFAULT_API_PORT = 3003
$script:DEFAULT_WEB_PORT = 5173

# Set ports from parameters or environment or defaults
if ($PostgresPort -gt 0) { $script:POSTGRES_PORT = $PostgresPort }
elseif ($env:POSTGRES_PORT) { $script:POSTGRES_PORT = [int]$env:POSTGRES_PORT }
else { $script:POSTGRES_PORT = $script:DEFAULT_POSTGRES_PORT }

if ($RedisPort -gt 0) { $script:REDIS_PORT = $RedisPort }
elseif ($env:REDIS_PORT) { $script:REDIS_PORT = [int]$env:REDIS_PORT }
else { $script:REDIS_PORT = $script:DEFAULT_REDIS_PORT }

if ($ApiPort -gt 0) { $script:API_PORT = $ApiPort }
elseif ($env:API_PORT) { $script:API_PORT = [int]$env:API_PORT }
else { $script:API_PORT = $script:DEFAULT_API_PORT }

if ($WebPort -gt 0) { $script:WEB_PORT = $WebPort }
elseif ($env:WEB_PORT) { $script:WEB_PORT = [int]$env:WEB_PORT }
else { $script:WEB_PORT = $script:DEFAULT_WEB_PORT }

# ===========================================
# Output Functions
# ===========================================
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

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Show-Help {
    Write-Host ""
    Write-Host "Grammarly Clone - Start Script (Windows)"
    Write-Host ""
    Write-Host "Usage: .\start.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Auto              Automatic mode (use fallback ports without asking)"
    Write-Host "  -Help              Show this help"
    Write-Host "  -PostgresPort N    Set PostgreSQL port"
    Write-Host "  -RedisPort N       Set Redis port"
    Write-Host "  -ApiPort N         Set API server port"
    Write-Host "  -WebPort N         Set Web frontend port"
    Write-Host ""
    Write-Host "Environment Variables:"
    Write-Host "  POSTGRES_PORT=5434  PostgreSQL port"
    Write-Host "  REDIS_PORT=6381     Redis port"
    Write-Host "  API_PORT=3003       API server port"
    Write-Host "  WEB_PORT=5173       Web frontend port"
    Write-Host ""
}

# ===========================================
# Port Detection Functions
# ===========================================

function Test-PortInUse {
    param([int]$Port)
    
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        return ($null -ne $connections -and $connections.Count -gt 0)
    }
    catch {
        # Fallback: try netstat
        try {
            $result = netstat -ano | Select-String ":$Port\s+.*LISTENING"
            return ($null -ne $result)
        }
        catch {
            return $false
        }
    }
}

function Find-AvailablePort {
    param(
        [int]$StartPort,
        [int]$MaxAttempts = 10
    )
    
    $port = $StartPort
    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        if (-not (Test-PortInUse -Port $port)) {
            return $port
        }
        $port++
    }
    return $null
}

function Get-PortProcess {
    param([int]$Port)
    
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($connection) {
            $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
            if ($process) {
                return "$($process.ProcessName) (PID: $($process.Id))"
            }
        }
    }
    catch {}
    
    return "unknown process"
}

function Test-PortConflicts {
    Write-Step "Checking port availability..."
    
    $conflicts = @()
    $portChanges = @()
    
    # Check PostgreSQL port
    if (Test-PortInUse -Port $script:POSTGRES_PORT) {
        $process = Get-PortProcess -Port $script:POSTGRES_PORT
        Write-Warning-Custom "Port $($script:POSTGRES_PORT) (PostgreSQL) is in use by: $process"
        $newPort = Find-AvailablePort -StartPort ($script:POSTGRES_PORT + 1)
        if ($newPort) {
            $conflicts += "PostgreSQL: $($script:POSTGRES_PORT) -> $newPort"
            $portChanges += "`$env:POSTGRES_PORT=$newPort"
            $script:POSTGRES_PORT = $newPort
        }
        else {
            Write-Error-Custom "No available port found for PostgreSQL"
            exit 1
        }
    }
    
    # Check Redis port
    if (Test-PortInUse -Port $script:REDIS_PORT) {
        $process = Get-PortProcess -Port $script:REDIS_PORT
        Write-Warning-Custom "Port $($script:REDIS_PORT) (Redis) is in use by: $process"
        $newPort = Find-AvailablePort -StartPort ($script:REDIS_PORT + 1)
        if ($newPort) {
            $conflicts += "Redis: $($script:REDIS_PORT) -> $newPort"
            $portChanges += "`$env:REDIS_PORT=$newPort"
            $script:REDIS_PORT = $newPort
        }
        else {
            Write-Error-Custom "No available port found for Redis"
            exit 1
        }
    }
    
    # Check API port
    if (Test-PortInUse -Port $script:API_PORT) {
        $process = Get-PortProcess -Port $script:API_PORT
        Write-Warning-Custom "Port $($script:API_PORT) (API) is in use by: $process"
        $newPort = Find-AvailablePort -StartPort ($script:API_PORT + 1)
        if ($newPort) {
            $conflicts += "API: $($script:API_PORT) -> $newPort"
            $portChanges += "`$env:API_PORT=$newPort"
            $script:API_PORT = $newPort
        }
        else {
            Write-Error-Custom "No available port found for API"
            exit 1
        }
    }
    
    # Check Web port
    if (Test-PortInUse -Port $script:WEB_PORT) {
        $process = Get-PortProcess -Port $script:WEB_PORT
        Write-Warning-Custom "Port $($script:WEB_PORT) (Web) is in use by: $process"
        $newPort = Find-AvailablePort -StartPort ($script:WEB_PORT + 1)
        if ($newPort) {
            $conflicts += "Web: $($script:WEB_PORT) -> $newPort"
            $portChanges += "`$env:WEB_PORT=$newPort"
            $script:WEB_PORT = $newPort
        }
        else {
            Write-Error-Custom "No available port found for Web"
            exit 1
        }
    }
    
    # If conflicts were found
    if ($conflicts.Count -gt 0) {
        Write-Host ""
        Write-Host "Port conflicts detected! Suggested fallback ports:" -ForegroundColor Yellow
        foreach ($conflict in $conflicts) {
            Write-Host "  - $conflict"
        }
        Write-Host ""
        
        if ($Auto) {
            Write-Step "Auto-mode: Using fallback ports"
        }
        else {
            $response = Read-Host "Use these fallback ports? (Y/n)"
            if ($response -eq 'n' -or $response -eq 'N') {
                Write-Host ""
                Write-Host "You can manually set ports via environment variables:"
                foreach ($change in $portChanges) {
                    Write-Host "  $change"
                }
                Write-Host ""
                Write-Host "Or stop the processes using these ports and try again."
                exit 0
            }
        }
        
        # Update docker-compose override
        Update-PortConfiguration
    }
    else {
        Write-Success "All ports are available"
    }
}

function Update-PortConfiguration {
    Write-Step "Updating port configuration..."
    
    $overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
    
    $content = @"
# ===========================================
# Docker Compose Override - Auto-generated
# Generated due to port conflicts
# ===========================================
services:
  postgres:
    ports:
      - "$($script:POSTGRES_PORT):5432"

  redis:
    ports:
      - "$($script:REDIS_PORT):6379"
"@
    
    Set-Content -Path $overrideFile -Value $content -Encoding UTF8
    Write-Success "Created docker-compose.override.yml with fallback ports"
    
    # Update API .env if it exists
    $apiEnv = Join-Path $ProjectRoot "apps\api\.env"
    if (Test-Path $apiEnv) {
        $envContent = Get-Content $apiEnv -Raw
        
        # Update DATABASE_URL
        $envContent = $envContent -replace 'postgresql://postgres:postgres@localhost:\d+/grammarly_clone', "postgresql://postgres:postgres@localhost:$($script:POSTGRES_PORT)/grammarly_clone"
        
        # Update REDIS_URL
        $envContent = $envContent -replace 'redis://localhost:\d+', "redis://localhost:$($script:REDIS_PORT)"
        
        Set-Content -Path $apiEnv -Value $envContent -Encoding UTF8
        Write-Success "Updated apps\api\.env with new ports"
    }
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

    # Start dev services with override if exists
    $overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
    if (Test-Path $overrideFile) {
        docker-compose -f docker-compose.dev.yml -f docker-compose.override.yml up -d
    }
    else {
        docker-compose -f docker-compose.dev.yml up -d
    }

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
                Write-Success "PostgreSQL is ready (port $($script:POSTGRES_PORT))"
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
                Write-Success "Redis is ready (port $($script:REDIS_PORT))"
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
    Write-Host "http://localhost:$($script:WEB_PORT)" -ForegroundColor Cyan
    Write-Host "  API:  " -NoNewline
    Write-Host "http://localhost:$($script:API_PORT)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Database Ports:"
    Write-Host "    PostgreSQL: " -NoNewline
    Write-Host "localhost:$($script:POSTGRES_PORT)" -ForegroundColor Cyan
    Write-Host "    Redis:      " -NoNewline
    Write-Host "localhost:$($script:REDIS_PORT)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Press " -NoNewline
    Write-Host "Ctrl+C" -ForegroundColor Yellow -NoNewline
    Write-Host " to stop"
    Write-Host ""

    # Export ports for npm scripts
    $env:PORT = $script:API_PORT
    $env:VITE_PORT = $script:WEB_PORT

    # Start the dev server
    npm run dev
}

# Main
function Main {
    if ($Help) {
        Show-Help
        exit 0
    }

    Write-Banner
    Test-Docker
    Test-PortConflicts
    Start-DockerServices
    Wait-ForServices
    Test-Environment
    Start-Application
}

Main
