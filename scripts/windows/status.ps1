# ===========================================
# Grammarly Clone - Service Status Script
# ===========================================
#
# Shows the status of all project services
#
# Usage:
#   .\status.ps1              # Show basic status
#   .\status.ps1 -Detailed    # Show detailed status with logs
#   .\status.ps1 -Json        # Output as JSON
# ===========================================

param(
    [switch]$Detailed,
    [switch]$Json,
    [switch]$Help
)

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Default ports
$script:REDIS_PORT = 6381
$script:API_PORT = 3003
$script:WEB_PORT = 5173

# Check if override file exists and read ports
$overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
if (Test-Path $overrideFile) {
    $content = Get-Content $overrideFile -Raw
    if ($content -match '(\d+):6379') { $script:REDIS_PORT = [int]$Matches[1] }
}

$script:REDIS_CONTAINER = "grammarly_remotedb_redis"
$script:API_CONTAINER = "grammarly_remotedb_api"
$script:WEB_CONTAINER = "grammarly_remotedb_web"

function Show-Help {
    Write-Host ""
    Write-Host "Grammarly Clone - Service Status"
    Write-Host ""
    Write-Host "Usage: .\status.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Detailed    Show detailed status with resource usage and logs"
    Write-Host "  -Json        Output status as JSON"
    Write-Host "  -Help        Show this help"
    Write-Host ""
}

function Test-DockerRunning {
    try {
        $null = docker info 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Get-ContainerStatus {
    param([string]$Container)
    try {
        $status = docker inspect -f '{{.State.Status}}' $Container 2>$null
        return $status
    }
    catch {
        return "not found"
    }
}

function Get-ContainerHealth {
    param([string]$Container)
    try {
        $health = docker inspect -f '{{.State.Health.Status}}' $Container 2>$null
        return $health
    }
    catch {
        return ""
    }
}

function Get-ContainerUptime {
    param([string]$Container)
    try {
        $started = docker inspect -f '{{.State.StartedAt}}' $Container 2>$null
        if ($started -and $started -ne "0001-01-01T00:00:00Z") {
            $startTime = [DateTime]::Parse($started.Substring(0, 19))
            $uptime = (Get-Date) - $startTime
            
            if ($uptime.TotalMinutes -lt 1) {
                return "$([math]::Floor($uptime.TotalSeconds))s"
            }
            elseif ($uptime.TotalHours -lt 1) {
                return "$([math]::Floor($uptime.TotalMinutes))m"
            }
            elseif ($uptime.TotalDays -lt 1) {
                return "$([math]::Floor($uptime.TotalHours))h $([math]::Floor($uptime.TotalMinutes % 60))m"
            }
            else {
                return "$([math]::Floor($uptime.TotalDays))d $([math]::Floor($uptime.TotalHours % 24))h"
            }
        }
        return "N/A"
    }
    catch {
        return "N/A"
    }
}

function Test-PortListening {
    param([int]$Port)
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        return $null -ne $connections
    }
    catch {
        return $false
    }
}

function Get-RedisClients {
    try {
        $result = docker exec $script:REDIS_CONTAINER redis-cli info clients 2>$null
        if ($result -match 'connected_clients:(\d+)') {
            return $Matches[1]
        }
        return ""
    }
    catch {
        return ""
    }
}

function Write-ServiceStatus {
    param(
        [string]$Name,
        [string]$Status,
        [int]$Port,
        [string]$Extra
    )
    
    $icon = switch ($Status) {
        "running" { "●"; $color = "Green" }
        "healthy" { "●"; $color = "Green" }
        "unhealthy" { "●"; $color = "Red" }
        "starting" { "◐"; $color = "Yellow" }
        { $_ -in "stopped", "exited", "not found" } { "○"; $color = "Red" }
        default { "?"; $color = "Yellow" }
    }
    
    Write-Host "  " -NoNewline
    Write-Host $icon -ForegroundColor $color -NoNewline
    Write-Host " " -NoNewline
    Write-Host ("{0,-20}" -f $Name) -NoNewline
    Write-Host ("{0,-12}" -f $Status) -NoNewline
    if ($Port -gt 0) {
        Write-Host ("Port: {0,-8}" -f $Port) -NoNewline
    }
    if ($Extra) {
        Write-Host $Extra -NoNewline
    }
    Write-Host ""
}

function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    if (-not $Json) {
        Write-Host ""
        Write-Host "===========================================" -ForegroundColor Blue
        Write-Host "     Grammarly Clone - Service Status" -ForegroundColor Blue
        Write-Host "===========================================" -ForegroundColor Blue
        Write-Host ""
    }
    
    # Check Docker
    if (-not (Test-DockerRunning)) {
        if ($Json) {
            Write-Output '{"status":"error","message":"Docker is not running"}'
        }
        else {
            Write-Host "  ✗ Docker is not running" -ForegroundColor Red
        }
        return
    }
    
    # Gather status
    $redisStatus = Get-ContainerStatus $script:REDIS_CONTAINER
    $redisHealth = Get-ContainerHealth $script:REDIS_CONTAINER
    $redisUptime = Get-ContainerUptime $script:REDIS_CONTAINER
    $redisClients = if ($redisStatus -eq "running") { Get-RedisClients } else { "" }
    
    $dbConnStatus = "checking..."
    if ($apiStatus -eq "running") {
        $dbCheck = docker exec $script:API_CONTAINER npx prisma db pull --print 2>$null
        if ($LASTEXITCODE -eq 0) { $dbConnStatus = "connected" } else { $dbConnStatus = "failed" }
    }
    else {
        $dbConnStatus = "offline"
    }
    
    $apiStatus = if (Test-PortListening $script:API_PORT) { "running" } else { "stopped" }
    $webStatus = if (Test-PortListening $script:WEB_PORT) { "running" } else { "stopped" }
    
    if ($Json) {
        $output = @{
            timestamp = (Get-Date -Format "o")
            services  = @{
                postgresql = @{
                    status     = "remote"
                    provider   = "Neon"
                    connection = $dbConnStatus
                }
                redis      = @{
                    status  = $redisStatus
                    health  = $redisHealth
                    port    = $script:REDIS_PORT
                    uptime  = $redisUptime
                    clients = $redisClients
                }
                api        = @{
                    status = $apiStatus
                    port   = $script:API_PORT
                }
                web        = @{
                    status = $webStatus
                    port   = $script:WEB_PORT
                }
            }
        }
        $output | ConvertTo-Json -Depth 3
        return
    }
    
    # Print status
    if ($dbConnStatus -eq "connected") {
        Write-Host "  ● " -ForegroundColor Green -NoNewline
        Write-Host "PostgreSQL          " -NoNewline
        Write-Host "remote      " -ForegroundColor Green -NoNewline
        Write-Host "Connected to Neon"
    }
    else {
        Write-Host "  ● " -ForegroundColor Red -NoNewline
        Write-Host "PostgreSQL          " -NoNewline
        Write-Host "remote      " -ForegroundColor Red -NoNewline
        Write-Host "$dbConnStatus"
    }
    
    $redisExtra = ""
    if ($redisClients) { $redisExtra = "Clients: $redisClients " }
    $redisExtra += "(uptime: $redisUptime)"
    Write-ServiceStatus "Redis" $(if ($redisHealth) { $redisHealth } else { $redisStatus }) $script:REDIS_PORT $redisExtra
    
    Write-ServiceStatus "API Server" $apiStatus $script:API_PORT ""
    Write-ServiceStatus "Web Frontend" $webStatus $script:WEB_PORT ""
    
    # Detailed output
    if ($Detailed) {
        Write-Host ""
        Write-Host "Docker Containers:" -ForegroundColor Cyan
        docker ps --filter "name=grammarly_remotedb" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
        
        Write-Host ""
        Write-Host "Resource Usage:" -ForegroundColor Cyan
        $containers = docker ps -q --filter "name=grammarly_remotedb"
        if ($containers) {
            docker stats --no-stream --format "table {{.Name}}`t{{.CPUPerc}}`t{{.MemUsage}}" $containers
        }
        
        Write-Host ""
        Write-Host "Recent Logs (last 5 lines each):" -ForegroundColor Cyan
        Write-Host "API Logs:" -ForegroundColor Yellow
        docker logs --tail 5 $script:API_CONTAINER 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Redis:" -ForegroundColor Yellow
        docker logs --tail 5 $script:REDIS_CONTAINER 2>&1 | ForEach-Object { Write-Host "  $_" }
    }
    
    Write-Host ""
    Write-Host "Quick Links:" -ForegroundColor Cyan
    Write-Host "  Web:  " -NoNewline
    Write-Host "http://localhost:$($script:WEB_PORT)" -ForegroundColor Blue
    Write-Host "  API:  " -NoNewline
    Write-Host "http://localhost:$($script:API_PORT)" -ForegroundColor Blue
    Write-Host ""
}

Main
