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
$script:POSTGRES_PORT = 5434
$script:REDIS_PORT = 6381
$script:API_PORT = 3003
$script:WEB_PORT = 5173

# Check if override file exists and read ports
$overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
if (Test-Path $overrideFile) {
    $content = Get-Content $overrideFile -Raw
    if ($content -match '(\d+):5432') { $script:POSTGRES_PORT = [int]$Matches[1] }
    if ($content -match '(\d+):6379') { $script:REDIS_PORT = [int]$Matches[1] }
}

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

function Get-PostgresConnections {
    try {
        $result = docker exec grammarly_postgres psql -U postgres -d grammarly_clone -t -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'grammarly_clone';" 2>$null
        return $result.Trim()
    }
    catch {
        return ""
    }
}

function Get-RedisClients {
    try {
        $result = docker exec grammarly_redis redis-cli info clients 2>$null
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
    $pgStatus = Get-ContainerStatus "grammarly_postgres"
    $pgHealth = Get-ContainerHealth "grammarly_postgres"
    $pgUptime = Get-ContainerUptime "grammarly_postgres"
    $pgConns = if ($pgStatus -eq "running") { Get-PostgresConnections } else { "" }
    
    $redisStatus = Get-ContainerStatus "grammarly_redis"
    $redisHealth = Get-ContainerHealth "grammarly_redis"
    $redisUptime = Get-ContainerUptime "grammarly_redis"
    $redisClients = if ($redisStatus -eq "running") { Get-RedisClients } else { "" }
    
    $apiStatus = if (Test-PortListening $script:API_PORT) { "running" } else { "stopped" }
    $webStatus = if (Test-PortListening $script:WEB_PORT) { "running" } else { "stopped" }
    
    if ($Json) {
        $output = @{
            timestamp = (Get-Date -Format "o")
            services  = @{
                postgresql = @{
                    status      = $pgStatus
                    health      = $pgHealth
                    port        = $script:POSTGRES_PORT
                    uptime      = $pgUptime
                    connections = $pgConns
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
    $pgExtra = ""
    if ($pgConns) { $pgExtra = "Connections: $pgConns " }
    $pgExtra += "(uptime: $pgUptime)"
    Write-ServiceStatus "PostgreSQL" $(if ($pgHealth) { $pgHealth } else { $pgStatus }) $script:POSTGRES_PORT $pgExtra
    
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
        docker ps --filter "name=grammarly" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
        
        Write-Host ""
        Write-Host "Resource Usage:" -ForegroundColor Cyan
        $containers = docker ps -q --filter "name=grammarly"
        if ($containers) {
            docker stats --no-stream --format "table {{.Name}}`t{{.CPUPerc}}`t{{.MemUsage}}" $containers
        }
        
        Write-Host ""
        Write-Host "Recent Logs (last 5 lines each):" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "PostgreSQL:" -ForegroundColor Yellow
        docker logs --tail 5 grammarly_postgres 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Redis:" -ForegroundColor Yellow
        docker logs --tail 5 grammarly_redis 2>&1 | ForEach-Object { Write-Host "  $_" }
    }
    
    Write-Host ""
    Write-Host "Quick Links:" -ForegroundColor Cyan
    Write-Host "  Web:  " -NoNewline
    Write-Host "http://localhost:$($script:WEB_PORT)" -ForegroundColor Blue
    Write-Host "  API:  " -NoNewline
    Write-Host "http://localhost:$($script:API_PORT)" -ForegroundColor Blue
    Write-Host ""
    Write-Host "Nginx Proxy Config:" -ForegroundColor Cyan
    Write-Host "  Frontend -> " -NoNewline
    Write-Host "http://127.0.0.1:$($script:WEB_PORT)" -ForegroundColor Blue
    Write-Host "  Backend  -> " -NoNewline
    Write-Host "http://127.0.0.1:$($script:API_PORT)" -ForegroundColor Blue
    Write-Host ""
}

Main
