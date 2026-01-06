# ===========================================
# Grammarly Clone - Windows Setup Script
# ===========================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Banner {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "  Grammarly Clone - Windows Setup"         -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Green
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
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Test-NodeJS {
    Write-Step "Checking Node.js..."

    try {
        $nodeVersion = node -v 2>&1
        if ($nodeVersion -match "v(\d+)") {
            $majorVersion = [int]$Matches[1]
            if ($majorVersion -ge 18) {
                Write-Success "Node.js installed: $nodeVersion"
                return $true
            }
            else {
                Write-Warning-Custom "Node.js version is less than 18. Please install Node.js 20+"
                Write-Host "Download from: https://nodejs.org/"
                return $false
            }
        }
    }
    catch {
        Write-Error-Custom "Node.js not found. Please install Node.js 20+"
        Write-Host "Download from: https://nodejs.org/"
        return $false
    }
    return $false
}

function Test-Docker {
    Write-Step "Checking Docker..."

    try {
        $null = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Docker is not running. Please start Docker Desktop."
            return $false
        }
        Write-Success "Docker is running"
        return $true
    }
    catch {
        Write-Error-Custom "Docker not found. Please install Docker Desktop."
        Write-Host "Download from: https://www.docker.com/products/docker-desktop/"
        return $false
    }
}

function Install-Dependencies {
    Write-Step "Installing npm dependencies..."

    Set-Location $ProjectRoot
    npm install

    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to install npm dependencies"
        return $false
    }

    Write-Success "Dependencies installed"
    return $true
}

function New-EnvFile {
    Write-Step "Creating environment configuration..."

    $envFile = Join-Path $ProjectRoot "apps\api\.env"
    $envExample = Join-Path $ProjectRoot "apps\api\.env.example"

    if (Test-Path $envFile) {
        Write-Warning-Custom ".env file already exists. Creating backup..."
        $backup = "$envFile.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $envFile $backup
    }

    # Generate random JWT secret
    $jwtSecret = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 64 | ForEach-Object { [char]$_ })

    # Prompt for Groq API key
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Yellow
    Write-Host "  Groq API Key Configuration"              -ForegroundColor Yellow
    Write-Host "===========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To use AI features, you need a Groq API key."
    Write-Host "Get your free API key at: https://console.groq.com"
    Write-Host ""
    $groqKey = Read-Host "Enter your Groq API key (or press Enter to skip)"

    $envContent = @"
# Server
NODE_ENV=development
PORT=3003

# Database (Remote Neon DB)
DATABASE_URL=postgresql://neondb_owner:npg_GEtIZnPkM20N@ep-broad-term-af6syi55-pooler.c-2.us-west-2.aws.neon.tech/grammarly?sslmode=require

# Redis (via Docker)
REDIS_URL=redis://localhost:6381

# JWT
JWT_SECRET=$jwtSecret
JWT_EXPIRES_IN=7d
JWT_REFRESH_EXPIRES_IN=30d

# AI Provider
AI_PROVIDER=groq
GROQ_API_KEY=$groqKey

# CORS
CORS_ORIGIN=http://localhost:5173

# Logging
LOG_LEVEL=info
"@

    Set-Content -Path $envFile -Value $envContent
    Write-Success "Environment file created"
    return $true
}

function Start-DockerServices {
    Write-Step "Starting Docker services..."

    Set-Location $ProjectRoot
    docker-compose up -d

    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to start Docker services"
        return $false
    }

    Write-Success "Docker services started"
    return $true
}

function Wait-ForServices {
    Write-Step "Waiting for services to be ready..."

    # Wait for Redis
    $maxAttempts = 30

    # Wait for Redis
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $result = docker exec grammarly_remotedb_redis redis-cli ping 2>&1
            if ($result -match "PONG") {
                Write-Success "Redis is ready"
                break
            }
        }
        catch {}

        if ($i -eq $maxAttempts) {
            Write-Error-Custom "Redis failed to start"
            return $false
        }
        Start-Sleep -Seconds 1
    }

    return $true
}

function Initialize-Database {
    Write-Step "Setting up database..."

    Set-Location (Join-Path $ProjectRoot "apps\api")

    npx prisma generate
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to generate Prisma client"
        return $false
    }

    npx prisma migrate deploy
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to deploy database migrations"
        return $false
    }

    Write-Success "Database setup complete"
    return $true
}

function Show-FinalInstructions {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "  Setup Complete!"                          -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "To start the application:"
    Write-Host ""
    Write-Host "  npm run start:all" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or use the scripts:"
    Write-Host ""
    Write-Host "  .\scripts\start.ps1" -ForegroundColor Cyan -NoNewline
    Write-Host "  - Start everything"
    Write-Host "  .\scripts\stop.ps1" -ForegroundColor Cyan -NoNewline
    Write-Host "   - Stop Docker services"
    Write-Host ""
    Write-Host "Access the application:"
    Write-Host "  Web: " -NoNewline
    Write-Host "http://localhost:5173" -ForegroundColor Cyan
    Write-Host "  API: " -NoNewline
    Write-Host "http://localhost:3003" -ForegroundColor Cyan
    Write-Host ""
}

# Main
function Main {
    Write-Banner

    Write-Host "This script will:"
    Write-Host "  - Check Node.js and Docker"
    Write-Host "  - Install project dependencies"
    Write-Host "  - Configure environment"
    Write-Host "  - Start Docker services (Redis, Ollama)"
    Write-Host "  - Setup database (Remote)"
    Write-Host ""

    $continue = Read-Host "Continue? (Y/n)"
    if ($continue -eq "n" -or $continue -eq "N") {
        Write-Host "Setup cancelled."
        exit 0
    }

    if (-not (Test-NodeJS)) { exit 1 }
    if (-not (Test-Docker)) { exit 1 }
    if (-not (Install-Dependencies)) { exit 1 }
    if (-not (New-EnvFile)) { exit 1 }
    if (-not (Start-DockerServices)) { exit 1 }
    if (-not (Wait-ForServices)) { exit 1 }
    if (-not (Initialize-Database)) { exit 1 }

    Show-FinalInstructions
}

Main
