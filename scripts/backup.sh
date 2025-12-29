#!/bin/bash

# ===========================================
# Grammarly Clone - Backup Script
# ===========================================
#
# Creates backups of database and/or application data
#
# Usage:
#   ./backup.sh                    # Full backup (database + files)
#   ./backup.sh --db               # Database only
#   ./backup.sh --files            # Files only (uploads, configs)
#   ./backup.sh --restore FILE     # Restore from backup
#   ./backup.sh --list             # List available backups
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Backup configuration
BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
DATE_FORMAT=$(date +"%Y%m%d_%H%M%S")
POSTGRES_CONTAINER="grammarly_postgres"
POSTGRES_USER="postgres"
POSTGRES_DB="grammarly_clone"

# Parse arguments
BACKUP_DB=false
BACKUP_FILES=false
RESTORE_FILE=""
LIST_BACKUPS=false
FULL_BACKUP=true

for arg in "$@"; do
    case $arg in
        --db|-d)
            BACKUP_DB=true
            FULL_BACKUP=false
            ;;
        --files|-f)
            BACKUP_FILES=true
            FULL_BACKUP=false
            ;;
        --restore|-r)
            RESTORE_MODE=true
            ;;
        --list|-l)
            LIST_BACKUPS=true
            ;;
        --help|-h)
            echo "Grammarly Clone - Backup Script" >&2
            echo "" >&2
            echo "Usage: ./backup.sh [OPTIONS]" >&2
            echo "" >&2
            echo "Backup Options:" >&2
            echo "  --db, -d          Backup database only" >&2
            echo "  --files, -f       Backup files only (uploads, configs, .env)" >&2
            echo "  (no options)      Full backup (database + files)" >&2
            echo "" >&2
            echo "Management Options:" >&2
            echo "  --restore FILE    Restore from a backup file" >&2
            echo "  --list, -l        List available backups" >&2
            echo "  --help, -h        Show this help" >&2
            echo "" >&2
            echo "Environment Variables:" >&2
            echo "  BACKUP_DIR        Custom backup directory (default: ./backups)" >&2
            echo "" >&2
            exit 0
            ;;
        *)
            if [ "$RESTORE_MODE" = true ]; then
                RESTORE_FILE="$arg"
                RESTORE_MODE=false
            fi
            ;;
    esac
done

# If full backup, enable both
if [ "$FULL_BACKUP" = true ]; then
    BACKUP_DB=true
    BACKUP_FILES=true
fi

# Output functions
print_step() {
    echo -e "${GREEN}[*]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_header() {
    echo -e "${BLUE}" >&2
    echo "===========================================" >&2
    echo "     Grammarly Clone - Backup Tool" >&2
    echo "===========================================" >&2
    echo -e "${NC}" >&2
}

# Create backup directory
ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        print_step "Created backup directory: $BACKUP_DIR"
    fi
}

# Check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        print_error "Docker is not running"
        exit 1
    fi
}

# Check if PostgreSQL container is running
check_postgres() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
        print_error "PostgreSQL container is not running"
        exit 1
    fi
}

# Get the correct docker-compose command
get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        print_error "Neither 'docker-compose' nor 'docker compose' is available"
        exit 1
    fi
}

# Backup database
backup_database() {
    print_step "Backing up PostgreSQL database..."
    
    check_docker
    check_postgres
    
    local db_backup_file="$BACKUP_DIR/db_${DATE_FORMAT}.sql.gz"
    
    # Create database dump and compress
    docker exec $POSTGRES_CONTAINER pg_dump -U $POSTGRES_USER -d $POSTGRES_DB | gzip > "$db_backup_file"
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$db_backup_file" | cut -f1)
        print_success "Database backup created: $db_backup_file ($size)"
        echo "$db_backup_file"
    else
        print_error "Failed to backup database"
        rm -f "$db_backup_file"
        exit 1
    fi
}

# Backup files
backup_files() {
    print_step "Backing up application files..."
    
    local files_backup_file="$BACKUP_DIR/files_${DATE_FORMAT}.tar.gz"
    local temp_dir=$(mktemp -d)
    
    # Files to backup
    local backup_items=()
    
    # .env files
    if [ -f "$PROJECT_ROOT/apps/api/.env" ]; then
        cp "$PROJECT_ROOT/apps/api/.env" "$temp_dir/api.env"
        backup_items+=("api.env")
    fi
    
    if [ -f "$PROJECT_ROOT/.env" ]; then
        cp "$PROJECT_ROOT/.env" "$temp_dir/root.env"
        backup_items+=("root.env")
    fi
    
    # Uploads directory
    if [ -d "$PROJECT_ROOT/apps/api/uploads" ]; then
        cp -r "$PROJECT_ROOT/apps/api/uploads" "$temp_dir/uploads"
        backup_items+=("uploads")
    fi
    
    # docker-compose.override.yml (port configuration)
    if [ -f "$PROJECT_ROOT/docker-compose.override.yml" ]; then
        cp "$PROJECT_ROOT/docker-compose.override.yml" "$temp_dir/"
        backup_items+=("docker-compose.override.yml")
    fi
    
    # Prisma migrations (important for schema)
    if [ -d "$PROJECT_ROOT/apps/api/prisma" ]; then
        cp -r "$PROJECT_ROOT/apps/api/prisma" "$temp_dir/prisma"
        backup_items+=("prisma")
    fi
    
    if [ ${#backup_items[@]} -eq 0 ]; then
        print_warning "No files to backup"
        rm -rf "$temp_dir"
        return
    fi
    
    # Create manifest
    echo "Backup created: $(date)" > "$temp_dir/manifest.txt"
    echo "Items: ${backup_items[*]}" >> "$temp_dir/manifest.txt"
    
    # Create tar archive
    tar -czf "$files_backup_file" -C "$temp_dir" .
    
    rm -rf "$temp_dir"
    
    local size=$(du -h "$files_backup_file" | cut -f1)
    print_success "Files backup created: $files_backup_file ($size)"
    echo "$files_backup_file"
}

# Create combined backup archive
create_combined_backup() {
    local db_file=$1
    local files_file=$2
    
    if [ -n "$db_file" ] && [ -n "$files_file" ]; then
        local combined_file="$BACKUP_DIR/backup_full_${DATE_FORMAT}.tar.gz"
        
        print_step "Creating combined backup archive..."
        
        local temp_dir=$(mktemp -d)
        cp "$db_file" "$temp_dir/"
        cp "$files_file" "$temp_dir/"
        
        # Create info file
        cat > "$temp_dir/backup_info.txt" << EOF
Grammarly Clone - Full Backup
==============================
Date: $(date)
Database: $(basename "$db_file")
Files: $(basename "$files_file")
EOF
        
        tar -czf "$combined_file" -C "$temp_dir" .
        rm -rf "$temp_dir"
        
        # Remove individual files
        rm -f "$db_file" "$files_file"
        
        local size=$(du -h "$combined_file" | cut -f1)
        print_success "Combined backup created: $combined_file ($size)"
    fi
}

# List backups
list_backups() {
    ensure_backup_dir
    
    echo -e "${CYAN}Available Backups:${NC}" >&2
    echo "" >&2
    
    local count=0
    shopt -s nullglob
    for file in "$BACKUP_DIR"/*.sql.gz "$BACKUP_DIR"/*.tar.gz; do
        if [ -f "$file" ]; then
            local size=$(du -h "$file" | cut -f1)
            local date=$(stat -c %y "$file" 2>/dev/null || stat -f %Sm "$file" 2>/dev/null)
            local basename=$(basename "$file")
            
            # Determine type
            local type=""
            if [[ "$basename" == db_* ]]; then
                type="[DB]"
            elif [[ "$basename" == files_* ]]; then
                type="[FILES]"
            elif [[ "$basename" == backup_full_* ]]; then
                type="[FULL]"
            else
                type="[?]"
            fi
            
            printf "  %-10s %-8s %s\n" "$type" "$size" "$basename" >&2
            ((count++))
        fi
    done
    shopt -u nullglob
    
    if [ $count -eq 0 ]; then
        echo "  No backups found in $BACKUP_DIR" >&2
    fi
    
    echo "" >&2
    echo "Total: $count backup(s)" >&2
}

# Stop Docker containers
stop_containers() {
    print_step "Stopping all containers..."
    
    check_docker
    
    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        print_warning "docker-compose.yml not found, skipping container stop"
        return
    fi
    
    local COMPOSE_CMD=$(get_docker_compose_cmd)
    
    cd "$PROJECT_ROOT"
    $COMPOSE_CMD down >&2 2>&1
    
    # Wait for containers to fully stop
    sleep 2
    
    print_success "All containers stopped"
}

# Start Docker containers
start_containers() {
    print_step "Starting all containers..."
    
    check_docker
    
    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        print_error "docker-compose.yml not found"
        exit 1
    fi
    
    local COMPOSE_CMD=$(get_docker_compose_cmd)
    
    cd "$PROJECT_ROOT"
    $COMPOSE_CMD up -d >&2 2>&1
    
    # Wait for containers to start
    print_step "Waiting for services to start..."
    sleep 5
    
    # Check container status
    local running_containers=$($COMPOSE_CMD ps --services --filter "status=running" 2>/dev/null | wc -l)
    
    print_success "Containers started ($running_containers services running)"
}

# Verify restore was successful
verify_restore() {
    print_step "Verifying restoration..."
    
    check_docker
    check_postgres
    
    # Wait a bit for PostgreSQL to be fully ready
    sleep 2
    
    # Test database connection
    if ! docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 1;" >&2 2>&1; then
        print_error "Database connection failed"
        return 1
    fi
    
    # Check if users table exists and count records
    local user_count=$(docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ')
    
    if [ -z "$user_count" ]; then
        print_warning "Could not verify user count (table may not exist yet)"
    else
        print_success "Database verified: $user_count user(s) found"
    fi
    
    # Check if API container is running
    if docker ps --format '{{.Names}}' | grep -q "grammarly_api"; then
        print_success "API container is running"
    else
        print_warning "API container is not running"
    fi
    
    print_success "Verification completed!"
}

# Restore from backup
restore_backup() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        # Try in backup directory
        if [ -f "$BACKUP_DIR/$backup_file" ]; then
            backup_file="$BACKUP_DIR/$backup_file"
        else
            print_error "Backup file not found: $backup_file"
            exit 1
        fi
    fi
    
    print_header
    print_warning "This will restore data from: $(basename "$backup_file")"
    print_warning "Existing data will be OVERWRITTEN!"
    echo "" >&2
    read -p "Are you sure you want to continue? (yes/no) " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Restore cancelled." >&2
        exit 0
    fi
    
    local temp_dir=$(mktemp -d)
    local basename=$(basename "$backup_file")
    
    # Determine backup type and extract
    if [[ "$basename" == backup_full_* ]]; then
        print_step "Extracting full backup..."
        tar -xzf "$backup_file" -C "$temp_dir"
        
        # Restore files FIRST (doesn't require containers)
        for files_file in "$temp_dir"/files_*.tar.gz; do
            if [ -f "$files_file" ]; then
                restore_files "$files_file"
            fi
        done
        
        # Stop and restart containers
        echo "" >&2
        stop_containers
        echo "" >&2
        start_containers
        echo "" >&2
        
        # Restore database AFTER containers are running
        for db_file in "$temp_dir"/db_*.sql.gz; do
            if [ -f "$db_file" ]; then
                restore_database "$db_file"
            fi
        done
        
    elif [[ "$basename" == db_* ]]; then
        # For database-only restore, ensure PostgreSQL is running
        restore_database "$backup_file"
        
    elif [[ "$basename" == files_* ]]; then
        # For files-only restore
        restore_files "$backup_file"
    else
        print_error "Unknown backup format"
        exit 1
    fi
    
    rm -rf "$temp_dir"
    
    echo "" >&2
    print_success "Restore completed!"
    
    # Verify restoration
    echo "" >&2
    verify_restore
}

restore_database() {
    local db_file=$1
    
    print_step "Restoring database..."
    
    check_docker
    check_postgres
    
    # Drop and recreate database
    docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};" 2>/dev/null || true
    docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -c "CREATE DATABASE ${POSTGRES_DB};" 2>/dev/null
    
    # Restore from dump
    gunzip -c "$db_file" | docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB
    
    print_success "Database restored"
}

restore_files() {
    local files_file=$1
    
    print_step "Restoring files..."
    
    local temp_dir=$(mktemp -d)
    tar -xzf "$files_file" -C "$temp_dir"
    
    # Restore .env files
    if [ -f "$temp_dir/api.env" ]; then
        cp "$temp_dir/api.env" "$PROJECT_ROOT/apps/api/.env"
        print_step "Restored apps/api/.env"
    fi
    
    if [ -f "$temp_dir/root.env" ]; then
        cp "$temp_dir/root.env" "$PROJECT_ROOT/.env"
        print_step "Restored .env"
    fi
    
    # Restore uploads
    if [ -d "$temp_dir/uploads" ]; then
        mkdir -p "$PROJECT_ROOT/apps/api/uploads"
        cp -r "$temp_dir/uploads/"* "$PROJECT_ROOT/apps/api/uploads/" 2>/dev/null || true
        print_step "Restored uploads"
    fi
    
    # Restore docker-compose.override.yml
    if [ -f "$temp_dir/docker-compose.override.yml" ]; then
        cp "$temp_dir/docker-compose.override.yml" "$PROJECT_ROOT/"
        print_step "Restored docker-compose.override.yml"
    fi
    
    rm -rf "$temp_dir"
    
    print_success "Files restored"
}

# Main function
main() {
    print_header
    ensure_backup_dir
    
    # Handle list mode
    if [ "$LIST_BACKUPS" = true ]; then
        list_backups
        exit 0
    fi
    
    # Handle restore mode
    if [ -n "$RESTORE_FILE" ]; then
        restore_backup "$RESTORE_FILE"
        exit 0
    fi
    
    # Perform backups
    local db_file=""
    local files_file=""
    
    if [ "$BACKUP_DB" = true ]; then
        db_file=$(backup_database)
    fi
    
    if [ "$BACKUP_FILES" = true ]; then
        files_file=$(backup_files)
    fi
    
    # Create combined archive if both were backed up
    if [ "$FULL_BACKUP" = true ] && [ -n "$db_file" ] && [ -n "$files_file" ]; then
        create_combined_backup "$db_file" "$files_file"
    fi
    
    echo "" >&2
    print_success "Backup completed!"
    echo "" >&2
    echo -e "${CYAN}Backup location: $BACKUP_DIR${NC}" >&2
}

main "$@"
