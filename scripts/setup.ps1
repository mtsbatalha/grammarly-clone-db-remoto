# ===========================================
# Grammarly Clone - Fresh Install Script (PowerShell)
# ===========================================
#
# Complete setup from scratch:
# - Stops and removes all containers
# - Removes all volumes (DATABASE WILL BE LOST!)
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
$ProjectRoot = Split-Path -Parent $ScriptDir

Set-Location $ProjectRoot

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

function Print-Header {
    Write-Host ""
    Write-Host "==========================================="  -ForegroundColor Blue
    Write-Host "  Grammarly Clone - Fresh Install" -ForegroundColor Blue
    Write-Host "==========================================="  -ForegroundColor Blue
    Write-Host ""
}

# Detect docker compose command
function Get-DockerComposeCmd {
    if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
        return "docker-compose"
    }
    elseif ((docker compose version 2>$null).ExitCode -eq 0) {
        return "docker compose"
    }
    else {
        Print-Error "Neither 'docker-compose' nor 'docker compose' is available"
        exit 1
    }
}

# Main installation function
Print-Header

Write-Host "⚠️  WARNING: This will:" -ForegroundColor Yellow
Write-Host "  - Stop and remove all containers" -ForegroundColor Yellow
Write-Host "  - Delete all volumes (DATABASE WILL BE LOST!)" -ForegroundColor Yellow
Write-Host "  - Rebuild everything from scratch" -ForegroundColor Yellow
Write-Host ""

if (-not $AutoConfirm) {
    $confirm = Read-Host "Continue? (type 'yes' to confirm)"
    if ($confirm -ne "yes") {
        Write-Host "Installation cancelled."
        exit 0
    }
}

Write-Host ""

# Detect docker compose
$ComposeCmd = Get-DockerComposeCmd
Print-Step "Using command: $ComposeCmd"

# Step 1: Stop and remove everything
Print-Step "Stopping and removing all containers..."
if ($ComposeCmd -eq "docker compose") {
    docker compose down -v --remove-orphans
}
else {
    docker-compose down -v --remove-orphans
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
if ($ComposeCmd -eq "docker compose") {
    docker compose up -d --build
}
else {
    docker-compose up -d --build
}
Print-Success "Containers started"

Write-Host ""

# Step 4: Wait for PostgreSQL to be ready
Print-Step "Waiting for PostgreSQL to be ready..."
for ($i = 1; $i -le 30; $i++) {
    $result = docker exec grammarly_postgres pg_isready -U postgres 2>&1
    if ($LASTEXITCODE -eq 0) {
        Print-Success "PostgreSQL is ready"
        break
    }
    Write-Host "  Waiting... ($i/30)"
    Start-Sleep -Seconds 2
}

# Extra wait for full readiness
Start-Sleep -Seconds 3

Write-Host ""

# Step 5: Run database migrations
Print-Step "Running Prisma migrations..."
docker exec grammarly_api npx prisma migrate deploy 2>&1
if ($LASTEXITCODE -eq 0) {
    Print-Success "Database migrations completed"
}
else {
    Print-Warning "Migration failed, trying reset..."
    docker exec grammarly_api npx prisma migrate reset --force
    Print-Success "Database reset completed"
}

Write-Host ""

# Step 6: Wait for API to be healthy
Print-Step "Waiting for API to be healthy..."
for ($i = 1; $i -le 30; $i++) {
    $logs = docker logs grammarly_api 2>&1 | Out-String
    if ($logs -match "Server running on") {
        Print-Success "API is running"
        break
    }
    Write-Host "  Waiting for API... ($i/30)"
    Start-Sleep -Seconds 2
}

Write-Host ""

# Step 7: Verify all services
Print-Step "Verifying all services..."

# Check PostgreSQL
docker exec grammarly_postgres psql -U postgres -d grammarly_clone -c "SELECT 1" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Print-Success "✓ PostgreSQL: Connected"
}
else {
    Print-Error "✗ PostgreSQL: Failed"
}

# Check Redis
docker exec grammarly_redis redis-cli ping 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Print-Success "✓ Redis: Connected"
}
else {
    Print-Error "✗ Redis: Failed"
}

# Check API health
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3002/health" -TimeoutSec 5 -ErrorAction Stop
    if ($response.Content -match "healthy") {
        Print-Success "✓ API: Healthy"
    }
}
catch {
    Print-Warning "✗ API: Not responding (check logs)"
}

# Check tables exist
$tableCount = docker exec grammarly_postgres psql -U postgres -d grammarly_clone -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>&1 | Out-String
$tableCount = $tableCount.Trim()
if ($tableCount -match '\d+' -and [int]$Matches[0] -gt 0) {
    Print-Success "✓ Database: $($Matches[0]) tables created"
}
else {
    Print-Error "✗ Database: No tables found"
}

Write-Host ""
Write-Host "==========================================="  -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "==========================================="  -ForegroundColor Green
Write-Host ""
Write-Host "Access your application:" -ForegroundColor Cyan
Write-Host "  🌐 Web Interface: " -NoNewline -ForegroundColor Cyan
Write-Host "http://localhost:5173" -ForegroundColor Blue
Write-Host "  🔌 API Server:    " -NoNewline -ForegroundColor Cyan
Write-Host "http://localhost:3002" -ForegroundColor Blue
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open http://localhost:5173 in your browser"
Write-Host "  2. Register a new user account"
Write-Host "  3. Start using Grammarly Clone!"
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Cyan
Write-Host "  Check status:     " -NoNewline -ForegroundColor Cyan
Write-Host ".\scripts\status.ps1" -ForegroundColor Blue
Write-Host "  View logs:        " -NoNewline -ForegroundColor Cyan
Write-Host "docker logs grammarly_api" -ForegroundColor Blue
Write-Host "  Stop all:         " -NoNewline -ForegroundColor Cyan
Write-Host "$ComposeCmd down" -ForegroundColor Blue
Write-Host "  Restart:          " -NoNewline -ForegroundColor Cyan
Write-Host ".\scripts\restart-containers.ps1" -ForegroundColor Blue
Write-Host ""
Write-Host ""
Write-Host "Nginx Configuration (Optional):" -ForegroundColor Cyan
Write-Host "If you are using Nginx as a reverse proxy, configure it to forward traffic:"
Write-Host "  - Frontend: proxy_pass http://localhost:5173;"
Write-Host "  - Backend:  proxy_pass http://localhost:3002;"
Write-Host ""
Write-Host "Example /etc/nginx/sites-available/grammarly:"
Write-Host "  server {"
Write-Host "      server_name your-domain.com;"
Write-Host "      location / { proxy_pass http://127.0.0.1:5173; }"
Write-Host "      location /api { proxy_pass http://127.0.0.1:3002; }"
Write-Host "  }"
Write-Host ""
