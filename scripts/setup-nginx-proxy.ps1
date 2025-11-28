# ===========================================
# NGINX Proxy Manager - Installation Script (Windows)
# ===========================================

$ErrorActionPreference = "Stop"

# Configuration
$NPM_HTTP_PORT = if ($env:NPM_HTTP_PORT) { $env:NPM_HTTP_PORT } else { "80" }
$NPM_HTTPS_PORT = if ($env:NPM_HTTPS_PORT) { $env:NPM_HTTPS_PORT } else { "443" }
$NPM_ADMIN_PORT = if ($env:NPM_ADMIN_PORT) { $env:NPM_ADMIN_PORT } else { "81" }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

function Write-Banner {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "  NGINX Proxy Manager - Setup"             -ForegroundColor Blue
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

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
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
        return $false
    }
}

function Get-DockerComposeCommand {
    Write-Step "Detecting Docker Compose command..."

    # Try new "docker compose" syntax first
    try {
        $null = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:DockerCompose = "docker compose"
            Write-Success "Using: docker compose"
            return $true
        }
    }
    catch {}

    # Try legacy "docker-compose" syntax
    try {
        $null = docker-compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:DockerCompose = "docker-compose"
            Write-Success "Using: docker-compose"
            return $true
        }
    }
    catch {}

    Write-Error-Custom "Docker Compose not found. Please install Docker Compose."
    return $false
}

function Test-Ports {
    Write-Step "Checking port availability..."

    $portsInUse = @()

    foreach ($port in @($NPM_HTTP_PORT, $NPM_HTTPS_PORT, $NPM_ADMIN_PORT)) {
        $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connection) {
            $portsInUse += $port
        }
    }

    if ($portsInUse.Count -gt 0) {
        Write-Warning-Custom "The following ports are already in use: $($portsInUse -join ', ')"
        Write-Host ""
        Write-Host "You can change ports by setting environment variables:"
        Write-Host '  $env:NPM_HTTP_PORT="8080"; $env:NPM_HTTPS_PORT="8443"; $env:NPM_ADMIN_PORT="8181"'
        Write-Host ""

        $continue = Read-Host "Continue anyway? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            return $false
        }
    }
    else {
        Write-Success "All ports available ($NPM_HTTP_PORT, $NPM_HTTPS_PORT, $NPM_ADMIN_PORT)"
    }

    return $true
}

function New-NpmDirectories {
    Write-Step "Creating directories..."

    $dataDir = Join-Path $ProjectRoot "nginx-proxy-manager\data"
    $letsencryptDir = Join-Path $ProjectRoot "nginx-proxy-manager\letsencrypt"

    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }

    if (-not (Test-Path $letsencryptDir)) {
        New-Item -ItemType Directory -Path $letsencryptDir -Force | Out-Null
    }

    Write-Success "Directories created"
}

function New-NpmCompose {
    Write-Step "Creating NGINX Proxy Manager configuration..."

    $composeFile = Join-Path $ProjectRoot "docker-compose.npm.yml"

    $composeContent = @"
# ===========================================
# NGINX Proxy Manager
# ===========================================
# Access admin panel at: http://localhost:${NPM_ADMIN_PORT}
# Default credentials:
#   Email:    admin@example.com
#   Password: changeme
# ===========================================

services:
  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '${NPM_HTTP_PORT}:80'      # HTTP
      - '${NPM_HTTPS_PORT}:443'    # HTTPS
      - '${NPM_ADMIN_PORT}:81'     # Admin Panel
    volumes:
      - ./nginx-proxy-manager/data:/data
      - ./nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    environment:
      - TZ=America/Sao_Paulo
    networks:
      - grammarly_network
      - npm_network

networks:
  grammarly_network:
    external: true
  npm_network:
    driver: bridge
"@

    Set-Content -Path $composeFile -Value $composeContent
    Write-Success "Configuration created"
}

function New-DockerNetwork {
    Write-Step "Creating Docker network..."

    $networkExists = docker network ls --format "{{.Name}}" | Where-Object { $_ -eq "grammarly_network" }

    if (-not $networkExists) {
        docker network create grammarly_network
        Write-Success "Network 'grammarly_network' created"
    }
    else {
        Write-Success "Network 'grammarly_network' already exists"
    }
}

function Start-NginxProxyManager {
    Write-Step "Starting NGINX Proxy Manager..."

    Set-Location $ProjectRoot

    if ($script:DockerCompose -eq "docker compose") {
        docker compose -f docker-compose.npm.yml up -d
    } else {
        docker-compose -f docker-compose.npm.yml up -d
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Failed to start NGINX Proxy Manager"
        return $false
    }

    Write-Success "NGINX Proxy Manager started"
    return $true
}

function Wait-ForNpm {
    Write-Step "Waiting for NGINX Proxy Manager to be ready..."

    for ($i = 1; $i -le 60; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$NPM_ADMIN_PORT/api/" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 401) {
                Write-Success "NGINX Proxy Manager is ready"
                return
            }
        }
        catch {
            # Still starting
        }
        Start-Sleep -Seconds 2
    }

    Write-Warning-Custom "NGINX Proxy Manager may still be starting. Check logs with: docker logs nginx-proxy-manager"
}

function Show-Instructions {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "  NGINX Proxy Manager Installed!"          -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Admin Panel:"
    Write-Host "  URL:      " -NoNewline
    Write-Host "http://localhost:$NPM_ADMIN_PORT" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Default Login:"
    Write-Host "  Email:    " -NoNewline
    Write-Host "admin@example.com" -ForegroundColor Yellow
    Write-Host "  Password: " -NoNewline
    Write-Host "changeme" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "IMPORTANT: Change the default password immediately!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Ports:"
    Write-Host "  HTTP:   $NPM_HTTP_PORT" -ForegroundColor Cyan
    Write-Host "  HTTPS:  $NPM_HTTPS_PORT" -ForegroundColor Cyan
    Write-Host "  Admin:  $NPM_ADMIN_PORT" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To configure proxy for Grammarly Clone:"
    Write-Host "  1. Open admin panel"
    Write-Host "  2. Add Proxy Host"
    Write-Host "  3. Domain: your-domain.com"
    Write-Host "  4. Forward Hostname: host.docker.internal"
    Write-Host "  5. Forward Port: 5173 (web) or 3003 (api)"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  $script:DockerCompose -f docker-compose.npm.yml logs -f" -ForegroundColor Cyan -NoNewline
    Write-Host "  - View logs"
    Write-Host "  $script:DockerCompose -f docker-compose.npm.yml down" -ForegroundColor Cyan -NoNewline
    Write-Host "     - Stop"
    Write-Host "  $script:DockerCompose -f docker-compose.npm.yml restart" -ForegroundColor Cyan -NoNewline
    Write-Host "  - Restart"
    Write-Host ""
}

# Main
function Main {
    Write-Banner

    Write-Host "This will install NGINX Proxy Manager for:"
    Write-Host "  - Reverse proxy to your applications"
    Write-Host "  - Free SSL certificates (Let's Encrypt)"
    Write-Host "  - Easy domain management"
    Write-Host ""
    Write-Host "Ports to be used:"
    Write-Host "  HTTP:  $NPM_HTTP_PORT"
    Write-Host "  HTTPS: $NPM_HTTPS_PORT"
    Write-Host "  Admin: $NPM_ADMIN_PORT"
    Write-Host ""

    $continue = Read-Host "Continue? (Y/n)"
    if ($continue -eq "n" -or $continue -eq "N") {
        Write-Host "Installation cancelled."
        exit 0
    }

    if (-not (Test-Docker)) { exit 1 }
    if (-not (Get-DockerComposeCommand)) { exit 1 }
    if (-not (Test-Ports)) { exit 1 }

    New-NpmDirectories
    New-DockerNetwork
    New-NpmCompose

    if (-not (Start-NginxProxyManager)) { exit 1 }

    Wait-ForNpm
    Show-Instructions
}

Main
