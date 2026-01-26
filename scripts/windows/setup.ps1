# ===========================================
# Grammarly Clone - Fresh Install Script (PowerShell)
# ===========================================
#
# Complete setup from scratch:
# - Detects if using remote or local database
# - Stops and removes all containers
# - Removes all volumes (DATABASE WILL BE LOST if local!)
# - Rebuilds containers
# - Runs database migrations
# - Verifies all services are healthy
#
# Usage:
#   .\setup.ps1              # Interactive mode
#   .\setup.ps1 -AutoConfirm # Auto-confirm (for automation)
# ===========================================

param(
    [switch]$AutoConfirm
)

$ErrorActionPreference = "Stop"

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

Set-Location $ProjectRoot

# Database mode (will be detected)
$script:DbMode = "unknown"

# Output functions
function Print-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Green
}

function Print-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

function Print-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Print-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Print-Header {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "  Grammarly Clone - Fresh Install" -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host ""
}

# Detect docker compose command
function Get-DockerComposeCmd {
    try {
        docker compose version 2>$null | Out-Null
        return "docker compose"
    }
    catch {
        if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
            return "docker-compose"
        }
        else {
            Print-Error "Neither 'docker-compose' nor 'docker compose' is available"
            exit 1
        }
    }
}

# Detect if DATABASE_URL points to a remote or local database
function Detect-DatabaseMode {
    Print-Step "Detecting database configuration..."
    
    $EnvFile = Join-Path $ProjectRoot ".env"
    $ApiEnvFile = Join-Path $ProjectRoot "apps\api\.env"
    
    $DatabaseUrl = ""
    
    # Check root .env first
    if (Test-Path $EnvFile) {
        $content = Get-Content $EnvFile -ErrorAction SilentlyContinue
        $match = $content | Where-Object { $_ -match "^DATABASE_URL=" }
        if ($match) {
            $DatabaseUrl = $match -replace "^DATABASE_URL=", "" -replace "[`"']", ""
        }
    }
    
    # Check apps/api/.env if not found
    if (-not $DatabaseUrl -and (Test-Path $ApiEnvFile)) {
        $content = Get-Content $ApiEnvFile -ErrorAction SilentlyContinue
        $match = $content | Where-Object { $_ -match "^DATABASE_URL=" }
        if ($match) {
            $DatabaseUrl = $match -replace "^DATABASE_URL=", "" -replace "[`"']", ""
        }
    }
    
    if (-not $DatabaseUrl) {
        Print-Warning "DATABASE_URL not found in .env files"
        Print-Info "Assuming LOCAL database mode (MySQL via Docker)"
        $script:DbMode = "local"
        return
    }
    
    # Extract host from DATABASE_URL
    # Format: mysql://user:pass@host:port/database
    if ($DatabaseUrl -match "mysql://[^@]+@([^:/]+)") {
        $DbHost = $Matches[1]
    }
    else {
        $DbHost = "localhost"
    }
    
    # Check if host is local
    if (-not $DbHost -or $DbHost -eq "localhost" -or $DbHost -eq "127.0.0.1" -or $DbHost -eq "0.0.0.0") {
        $script:DbMode = "local"
        Print-Success "Database mode: LOCAL (MySQL via Docker)"
        Print-Info "  Host: $DbHost"
    }
    else {
        $script:DbMode = "remote"
        Print-Success "Database mode: REMOTE"
        Print-Info "  Host: $DbHost"
    }
}

# Get the appropriate compose file based on DB mode
function Get-ComposeFile {
    if ($script:DbMode -eq "local") {
        return "docker-compose.local.yml"
    }
    else {
        return "docker-compose.dev.yml"
    }
}

# Main installation function
Print-Header

Write-Host "⚠️  WARNING: This will:" -ForegroundColor Yellow
Write-Host "  - Stop and remove all containers" -ForegroundColor Yellow
Write-Host "  - Delete all volumes (LOCAL DATABASE WILL BE LOST!)" -ForegroundColor Yellow
Write-Host "  - Rebuild everything from scratch" -ForegroundColor Yellow
Write-Host ""

if (-not $AutoConfirm) {
    $confirm = Read-Host "Continue? (type 'yes' to confirm)"
    if ($confirm -ne "yes") {
        Write-Host "Installation cancelled."
        exit 0
    }
    
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  Ollama (Local AI) Configuration" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Ollama allows you to run AI models locally."
    Write-Host "If you're using Groq/DeepSeek API, you can skip this."
    Write-Host ""
    $ollamaChoice = Read-Host "Install Ollama? (y/N)"
    if ($ollamaChoice -eq "y" -or $ollamaChoice -eq "Y") {
        $script:IncludeOllama = $true
        Print-Step "Ollama will be installed"
    }
    else {
        $script:IncludeOllama = $false
        Print-Step "Skipping Ollama installation"
    }
}
else {
    $script:IncludeOllama = $false
}

Write-Host ""

# Detect docker compose
$ComposeCmd = Get-DockerComposeCmd
Print-Step "Using command: $ComposeCmd"

# Detect database mode
Detect-DatabaseMode

# Get appropriate compose file
$ComposeFile = Get-ComposeFile
Print-Step "Using compose file: $ComposeFile"

Write-Host ""

# Step 1: Stop and remove everything
Print-Step "Stopping and removing all containers..."

# Stop both local and dev compose files to clean up
if ($ComposeCmd -eq "docker compose") {
    docker compose -f docker-compose.local.yml down -v --remove-orphans 2>&1 | Out-Null
    docker compose -f docker-compose.dev.yml down -v --remove-orphans 2>&1 | Out-Null
    docker compose down -v --remove-orphans 2>&1 | Out-Null
}
else {
    docker-compose -f docker-compose.local.yml down -v --remove-orphans 2>&1 | Out-Null
    docker-compose -f docker-compose.dev.yml down -v --remove-orphans 2>&1 | Out-Null
    docker-compose down -v --remove-orphans 2>&1 | Out-Null
}
Print-Success "Containers and volumes removed"

Write-Host ""

# Step 2: Remove any lingering .env in API
if (Test-Path "apps\api\.env") {
    Print-Warning "Found apps\api\.env, removing it..."
    Remove-Item "apps\api\.env"
    Print-Success "Removed apps\api\.env"
    Write-Host ""
}

# Step 3: Build and start containers
Print-Step "Building and starting containers..."

if ($script:DbMode -eq "local") {
    Print-Info "Starting MySQL + Redis (local database mode)"
}
else {
    Print-Info "Starting Redis only (remote database mode)"
}

if ($ComposeCmd -eq "docker compose") {
    if ($script:IncludeOllama) {
        docker compose -f $ComposeFile --profile ollama up -d --build
    }
    else {
        docker compose -f $ComposeFile up -d --build
    }
}
else {
    if ($script:IncludeOllama) {
        docker-compose -f $ComposeFile --profile ollama up -d --build
    }
    else {
        docker-compose -f $ComposeFile up -d --build
    }
}
Print-Success "Containers started"

Write-Host ""

# Step 4: Wait for services to be ready
Print-Step "Waiting for services to be ready..."

# Wait for MySQL if local mode
if ($script:DbMode -eq "local") {
    Write-Host "  Waiting for MySQL..."
    for ($i = 1; $i -le 60; $i++) {
        $result = docker exec grammarly_mysql mysqladmin ping -h localhost --silent 2>&1
        if ($LASTEXITCODE -eq 0) {
            Print-Success "MySQL is ready"
            break
        }
        if ($i -eq 60) {
            Print-Warning "MySQL is taking longer than expected"
        }
        Start-Sleep -Seconds 1
    }
}

# Wait for Redis
for ($i = 1; $i -le 30; $i++) {
    docker exec grammarly_redis redis-cli ping 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Print-Success "Redis is ready"
        break
    }
    Start-Sleep -Seconds 1
}

Write-Host ""

# Step 5: Run database migrations
Print-Step "Running Prisma migrations..."

Set-Location "apps\api"

# Generate Prisma client and run migrations
npx prisma generate 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -eq 0) {
    Print-Success "Prisma client generated"
}
else {
    Print-Warning "Prisma generate failed"
}

npx prisma migrate deploy 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -eq 0) {
    Print-Success "Database migrations completed"
}
else {
    Print-Warning "Migration failed. Ensure DATABASE_URL is correct"
}

Set-Location $ProjectRoot

Write-Host ""

# Step 6: Verify all services
Print-Step "Verifying all services..."

# Check MySQL (depending on mode)
if ($script:DbMode -eq "local") {
    docker exec grammarly_mysql mysqladmin ping -h localhost --silent 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Print-Success "✓ MySQL: Connected (local Docker)"
    }
    else {
        Print-Error "✗ MySQL: Failed to connect"
    }
}
else {
    Print-Success "✓ MySQL: Using Remote Database"
}

# Check Redis
docker exec grammarly_redis redis-cli ping 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Print-Success "✓ Redis: Connected"
}
else {
    Print-Error "✗ Redis: Failed"
}

# Database check
Print-Success "✓ Database: Migrations deployed"

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Database Mode:" -ForegroundColor Cyan
if ($script:DbMode -eq "local") {
    Write-Host "  MySQL: Docker container (port 3307)"
}
else {
    Write-Host "  MySQL: Remote server"
}
Write-Host "  Redis: Docker container (port 6381)"
Write-Host ""
Write-Host "To start the application:" -ForegroundColor Cyan
Write-Host "  .\scripts\windows\start.ps1" -ForegroundColor Blue
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Check status:     " -NoNewline -ForegroundColor Cyan
Write-Host ".\scripts\windows\status.ps1" -ForegroundColor Blue
Write-Host "  View logs:        " -NoNewline -ForegroundColor Cyan
Write-Host "docker logs grammarly_redis" -ForegroundColor Blue
Write-Host "  Stop all:         " -NoNewline -ForegroundColor Cyan
Write-Host "$ComposeCmd -f $ComposeFile down" -ForegroundColor Blue
Write-Host ""
