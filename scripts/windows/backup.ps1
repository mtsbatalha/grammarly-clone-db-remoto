# ===========================================
# Grammarly Clone - Backup Script
# ===========================================
#
# Creates backups of database and/or application data
#
# Usage:
#   .\backup.ps1                    # Full backup (database + files)
#   .\backup.ps1 -Database          # Database only
#   .\backup.ps1 -Files             # Files only (uploads, configs)
#   .\backup.ps1 -Restore FILE      # Restore from backup
#   .\backup.ps1 -List              # List available backups
# ===========================================

param(
    [switch]$Database,
    [switch]$Files,
    [string]$Restore,
    [switch]$List,
    [switch]$Help
)

# Get project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Configuration
$BackupDir = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { Join-Path $ProjectRoot "backups" }
$DateFormat = Get-Date -Format "yyyyMMdd_HHmmss"
$PostgresContainer = "grammarly_postgres"
$PostgresUser = "postgres"
$PostgresDb = "grammarly_clone"

# Determine backup mode
$FullBackup = (-not $Database -and -not $Files -and -not $List -and -not $Restore -and -not $Help)
if ($FullBackup) {
    $Database = $true
    $Files = $true
}

function Show-Help {
    Write-Host ""
    Write-Host "Grammarly Clone - Backup Script"
    Write-Host ""
    Write-Host "Usage: .\backup.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Backup Options:"
    Write-Host "  -Database         Backup database only"
    Write-Host "  -Files            Backup files only (uploads, configs, .env)"
    Write-Host "  (no options)      Full backup (database + files)"
    Write-Host ""
    Write-Host "Management Options:"
    Write-Host "  -Restore FILE     Restore from a backup file"
    Write-Host "  -List             List available backups"
    Write-Host "  -Help             Show this help"
    Write-Host ""
    Write-Host "Environment Variables:"
    Write-Host "  BACKUP_DIR        Custom backup directory (default: .\backups)"
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Green
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Header {
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host "     Grammarly Clone - Backup Tool" -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    Write-Host ""
}

function Ensure-BackupDir {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
        Write-Step "Created backup directory: $BackupDir"
    }
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

function Test-PostgresRunning {
    $containers = docker ps --format '{{.Names}}' 2>$null
    return $containers -contains $PostgresContainer
}

function Backup-Database {
    Write-Step "Backing up PostgreSQL database..."
    
    if (-not (Test-DockerRunning)) {
        Write-Error-Custom "Docker is not running"
        exit 1
    }
    
    if (-not (Test-PostgresRunning)) {
        Write-Error-Custom "PostgreSQL container is not running"
        exit 1
    }
    
    $dbBackupFile = Join-Path $BackupDir "db_${DateFormat}.sql"
    $dbBackupFileGz = "${dbBackupFile}.gz"
    
    # Create database dump
    docker exec $PostgresContainer pg_dump -U $PostgresUser -d $PostgresDb > $dbBackupFile
    
    if ($LASTEXITCODE -eq 0) {
        # Compress using PowerShell
        $content = Get-Content $dbBackupFile -Raw -Encoding UTF8
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        
        $ms = New-Object System.IO.MemoryStream
        $gzip = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
        $gzip.Write($bytes, 0, $bytes.Length)
        $gzip.Close()
        
        [System.IO.File]::WriteAllBytes($dbBackupFileGz, $ms.ToArray())
        $ms.Close()
        
        Remove-Item $dbBackupFile -Force
        
        $size = (Get-Item $dbBackupFileGz).Length / 1KB
        Write-Success "Database backup created: $dbBackupFileGz ($([math]::Round($size, 2)) KB)"
        return $dbBackupFileGz
    }
    else {
        Write-Error-Custom "Failed to backup database"
        Remove-Item $dbBackupFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

function Backup-Files {
    Write-Step "Backing up application files..."
    
    $filesBackupFile = Join-Path $BackupDir "files_${DateFormat}.zip"
    $tempDir = Join-Path $env:TEMP "grammarly_backup_$DateFormat"
    
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    $backupItems = @()
    
    # .env files
    $apiEnv = Join-Path $ProjectRoot "apps\api\.env"
    if (Test-Path $apiEnv) {
        Copy-Item $apiEnv (Join-Path $tempDir "api.env")
        $backupItems += "api.env"
    }
    
    $rootEnv = Join-Path $ProjectRoot ".env"
    if (Test-Path $rootEnv) {
        Copy-Item $rootEnv (Join-Path $tempDir "root.env")
        $backupItems += "root.env"
    }
    
    # Uploads directory
    $uploadsDir = Join-Path $ProjectRoot "apps\api\uploads"
    if (Test-Path $uploadsDir) {
        Copy-Item $uploadsDir (Join-Path $tempDir "uploads") -Recurse
        $backupItems += "uploads"
    }
    
    # docker-compose.override.yml
    $overrideFile = Join-Path $ProjectRoot "docker-compose.override.yml"
    if (Test-Path $overrideFile) {
        Copy-Item $overrideFile $tempDir
        $backupItems += "docker-compose.override.yml"
    }
    
    # Prisma directory
    $prismaDir = Join-Path $ProjectRoot "apps\api\prisma"
    if (Test-Path $prismaDir) {
        Copy-Item $prismaDir (Join-Path $tempDir "prisma") -Recurse
        $backupItems += "prisma"
    }
    
    if ($backupItems.Count -eq 0) {
        Write-Warning-Custom "No files to backup"
        Remove-Item $tempDir -Recurse -Force
        return $null
    }
    
    # Create manifest
    $manifest = @"
Backup created: $(Get-Date)
Items: $($backupItems -join ', ')
"@
    Set-Content -Path (Join-Path $tempDir "manifest.txt") -Value $manifest
    
    # Create zip archive
    Compress-Archive -Path "$tempDir\*" -DestinationPath $filesBackupFile -Force
    
    Remove-Item $tempDir -Recurse -Force
    
    $size = (Get-Item $filesBackupFile).Length / 1KB
    Write-Success "Files backup created: $filesBackupFile ($([math]::Round($size, 2)) KB)"
    return $filesBackupFile
}

function Create-CombinedBackup {
    param(
        [string]$DbFile,
        [string]$FilesFile
    )
    
    if ($DbFile -and $FilesFile) {
        $combinedFile = Join-Path $BackupDir "backup_full_${DateFormat}.zip"
        
        Write-Step "Creating combined backup archive..."
        
        $tempDir = Join-Path $env:TEMP "grammarly_combined_$DateFormat"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        Copy-Item $DbFile $tempDir
        Copy-Item $FilesFile $tempDir
        
        # Create info file
        $info = @"
Grammarly Clone - Full Backup
==============================
Date: $(Get-Date)
Database: $(Split-Path $DbFile -Leaf)
Files: $(Split-Path $FilesFile -Leaf)
"@
        Set-Content -Path (Join-Path $tempDir "backup_info.txt") -Value $info
        
        Compress-Archive -Path "$tempDir\*" -DestinationPath $combinedFile -Force
        
        Remove-Item $tempDir -Recurse -Force
        Remove-Item $DbFile -Force
        Remove-Item $FilesFile -Force
        
        $size = (Get-Item $combinedFile).Length / 1KB
        Write-Success "Combined backup created: $combinedFile ($([math]::Round($size, 2)) KB)"
    }
}

function Show-Backups {
    Ensure-BackupDir
    
    Write-Host "Available Backups:" -ForegroundColor Cyan
    Write-Host ""
    
    $backups = Get-ChildItem $BackupDir -Include "*.sql.gz", "*.zip" -Recurse -ErrorAction SilentlyContinue
    
    if ($backups.Count -eq 0) {
        Write-Host "  No backups found in $BackupDir"
    }
    else {
        foreach ($file in $backups | Sort-Object LastWriteTime -Descending) {
            $type = switch -Wildcard ($file.Name) {
                "db_*" { "[DB]" }
                "files_*" { "[FILES]" }
                "backup_full_*" { "[FULL]" }
                default { "[?]" }
            }
            
            $size = if ($file.Length -gt 1MB) {
                "$([math]::Round($file.Length / 1MB, 2)) MB"
            }
            else {
                "$([math]::Round($file.Length / 1KB, 2)) KB"
            }
            
            Write-Host ("  {0,-10} {1,-12} {2}" -f $type, $size, $file.Name)
        }
    }
    
    Write-Host ""
    Write-Host "Total: $($backups.Count) backup(s)"
}

function Restore-Backup {
    param([string]$BackupFile)
    
    # Find backup file
    if (-not (Test-Path $BackupFile)) {
        $fullPath = Join-Path $BackupDir $BackupFile
        if (Test-Path $fullPath) {
            $BackupFile = $fullPath
        }
        else {
            Write-Error-Custom "Backup file not found: $BackupFile"
            exit 1
        }
    }
    
    Write-Header
    Write-Warning-Custom "This will restore data from: $(Split-Path $BackupFile -Leaf)"
    Write-Warning-Custom "Existing data will be OVERWRITTEN!"
    Write-Host ""
    
    $confirm = Read-Host "Are you sure you want to continue? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Restore cancelled."
        exit 0
    }
    
    $fileName = Split-Path $BackupFile -Leaf
    $tempDir = Join-Path $env:TEMP "grammarly_restore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Determine backup type
    if ($fileName -like "backup_full_*") {
        Write-Step "Extracting full backup..."
        Expand-Archive -Path $BackupFile -DestinationPath $tempDir -Force
        
        # Restore database
        $dbFiles = Get-ChildItem $tempDir -Filter "db_*.sql.gz"
        foreach ($dbFile in $dbFiles) {
            Restore-Database -DbFile $dbFile.FullName
        }
        
        # Restore files
        $filesFiles = Get-ChildItem $tempDir -Filter "files_*.zip"
        foreach ($filesFile in $filesFiles) {
            Restore-Files -FilesFile $filesFile.FullName
        }
    }
    elseif ($fileName -like "db_*") {
        Restore-Database -DbFile $BackupFile
    }
    elseif ($fileName -like "files_*") {
        Restore-Files -FilesFile $BackupFile
    }
    else {
        Write-Error-Custom "Unknown backup format"
        exit 1
    }
    
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host ""
    Write-Success "Restore completed!"
}

function Restore-Database {
    param([string]$DbFile)
    
    Write-Step "Restoring database..."
    
    if (-not (Test-DockerRunning)) {
        Write-Error-Custom "Docker is not running"
        return
    }
    
    if (-not (Test-PostgresRunning)) {
        Write-Error-Custom "PostgreSQL container is not running"
        return
    }
    
    # Decompress
    $sqlFile = $DbFile -replace '\.gz$', ''
    
    $bytes = [System.IO.File]::ReadAllBytes($DbFile)
    $ms = New-Object System.IO.MemoryStream(, $bytes)
    $gzip = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
    $reader = New-Object System.IO.StreamReader($gzip)
    $content = $reader.ReadToEnd()
    $reader.Close()
    $gzip.Close()
    $ms.Close()
    
    Set-Content -Path $sqlFile -Value $content -Encoding UTF8
    
    # Drop and recreate database
    docker exec $PostgresContainer psql -U $PostgresUser -c "DROP DATABASE IF EXISTS ${PostgresDb};" 2>$null
    docker exec $PostgresContainer psql -U $PostgresUser -c "CREATE DATABASE ${PostgresDb};" 2>$null
    
    # Restore
    Get-Content $sqlFile | docker exec -i $PostgresContainer psql -U $PostgresUser -d $PostgresDb
    
    Remove-Item $sqlFile -Force
    
    Write-Success "Database restored"
}

function Restore-Files {
    param([string]$FilesFile)
    
    Write-Step "Restoring files..."
    
    $tempDir = Join-Path $env:TEMP "grammarly_files_restore"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    Expand-Archive -Path $FilesFile -DestinationPath $tempDir -Force
    
    # Restore .env files
    $apiEnv = Join-Path $tempDir "api.env"
    if (Test-Path $apiEnv) {
        Copy-Item $apiEnv (Join-Path $ProjectRoot "apps\api\.env") -Force
        Write-Step "Restored apps\api\.env"
    }
    
    $rootEnv = Join-Path $tempDir "root.env"
    if (Test-Path $rootEnv) {
        Copy-Item $rootEnv (Join-Path $ProjectRoot ".env") -Force
        Write-Step "Restored .env"
    }
    
    # Restore uploads
    $uploadsDir = Join-Path $tempDir "uploads"
    if (Test-Path $uploadsDir) {
        $destUploads = Join-Path $ProjectRoot "apps\api\uploads"
        New-Item -ItemType Directory -Path $destUploads -Force | Out-Null
        Copy-Item "$uploadsDir\*" $destUploads -Recurse -Force
        Write-Step "Restored uploads"
    }
    
    # Restore docker-compose.override.yml
    $overrideFile = Join-Path $tempDir "docker-compose.override.yml"
    if (Test-Path $overrideFile) {
        Copy-Item $overrideFile $ProjectRoot -Force
        Write-Step "Restored docker-compose.override.yml"
    }
    
    Remove-Item $tempDir -Recurse -Force
    
    Write-Success "Files restored"
}

# Main function
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Header
    Ensure-BackupDir
    
    if ($List) {
        Show-Backups
        return
    }
    
    if ($Restore) {
        Restore-Backup -BackupFile $Restore
        return
    }
    
    # Perform backups
    $dbFile = $null
    $filesFile = $null
    
    if ($Database) {
        $dbFile = Backup-Database
    }
    
    if ($Files) {
        $filesFile = Backup-Files
    }
    
    # Create combined if both
    if ($FullBackup -and $dbFile -and $filesFile) {
        Create-CombinedBackup -DbFile $dbFile -FilesFile $filesFile
    }
    
    Write-Host ""
    Write-Success "Backup completed!"
    Write-Host ""
    Write-Host "Backup location: $BackupDir" -ForegroundColor Cyan
}

Main
