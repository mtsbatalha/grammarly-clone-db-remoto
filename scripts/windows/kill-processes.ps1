# ===========================================
# Grammarly Clone - Kill Node.js Processes
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

# Configuration (matching docker-compose.yml)
$API_PORT = $env:API_PORT ?? 3003
$WEB_PORT = $env:WEB_PORT ?? 5173

function Kill-PortProcess {
    param(
        [int]$Port,
        [string]$PortName
    )
    
    Write-StepMessage "Checking for processes on port $Port ($PortName)..."
    
    try {
        $processes = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        
        if ($processes) {
            foreach ($proc in $processes) {
                $process = Get-Process -Id $proc.OwningProcess -ErrorAction SilentlyContinue
                if ($process) {
                    Write-WarningMessage "Found process on port $Port (PID: $($proc.OwningProcess)): $($process.ProcessName)"
                    Stop-Process -Id $proc.OwningProcess -Force -ErrorAction SilentlyContinue
                    Write-SuccessMessage "Killed process on port $Port"
                    Start-Sleep -Seconds 1
                }
            }
        } else {
            Write-StepMessage "No process found on port $Port"
        }
    } catch {
        Write-WarningMessage "Could not check port $Port : $_"
    }
}

# Main function
function Main {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  Killing Node.js Processes" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host ""
    
    Write-Host "This script will kill any processes running on:"
    Write-Host "  - API port:  $API_PORT"
    Write-Host "  - Web port:  $WEB_PORT"
    Write-Host ""
    
    $response = Read-Host "Continue? (y/N)"
    
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Cancelled."
        exit 0
    }
    
    Write-Host ""
    
    # Kill processes on both ports
    Kill-PortProcess -Port $API_PORT -PortName "API"
    Kill-PortProcess -Port $WEB_PORT -PortName "Web"
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "  All Node.js processes killed!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host ""
}

# Run main function
Main
