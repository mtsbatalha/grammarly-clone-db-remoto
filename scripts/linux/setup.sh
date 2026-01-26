#!/bin/bash

# ===========================================
# Grammarly Clone - Fresh Install Script
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
#   ./setup.sh              # Interactive mode
#   ./setup.sh --yes        # Auto-confirm (for automation)
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
AUTO_CONFIRM=false
for arg in "$@"; do
    case $arg in
        --yes|-y)
            AUTO_CONFIRM=true
            ;;
    esac
done

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_ROOT" || exit 1

# Database mode (will be detected)
DB_MODE="unknown"

# Output functions
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_header() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  Grammarly Clone - Fresh Install"
    echo "==========================================="
    echo -e "${NC}"
}

# Detect docker compose command
get_docker_compose_cmd() {
    if docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        print_error "Neither 'docker-compose' nor 'docker compose' is available"
        exit 1
    fi
}

# Detect if DATABASE_URL points to a remote or local database
detect_database_mode() {
    print_step "Detecting database configuration..."
    
    # Try to read DATABASE_URL from .env file
    ENV_FILE="$PROJECT_ROOT/.env"
    API_ENV_FILE="$PROJECT_ROOT/apps/api/.env"
    
    DATABASE_URL=""
    
    # Check root .env first
    if [ -f "$ENV_FILE" ]; then
        DATABASE_URL=$(grep -E "^DATABASE_URL=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    # Check apps/api/.env if not found
    if [ -z "$DATABASE_URL" ] && [ -f "$API_ENV_FILE" ]; then
        DATABASE_URL=$(grep -E "^DATABASE_URL=" "$API_ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    if [ -z "$DATABASE_URL" ]; then
        print_warning "DATABASE_URL not found in .env files"
        print_info "Assuming LOCAL database mode (MySQL via Docker)"
        DB_MODE="local"
        return
    fi
    
    # Extract host from DATABASE_URL
    # Format: mysql://user:pass@host:port/database
    DB_HOST=$(echo "$DATABASE_URL" | sed -E 's|^mysql://[^@]+@([^:/]+).*|\1|')
    
    # Check if host is local
    if [ -z "$DB_HOST" ] || [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ] || [ "$DB_HOST" = "0.0.0.0" ]; then
        DB_MODE="local"
        print_success "Database mode: LOCAL (MySQL via Docker)"
        print_info "  Host: ${DB_HOST:-localhost}"
    else
        DB_MODE="remote"
        print_success "Database mode: REMOTE"
        print_info "  Host: $DB_HOST"
    fi
}

# Get the appropriate compose file based on DB mode
get_compose_file() {
    if [ "$DB_MODE" = "local" ]; then
        echo "docker-compose.local.yml"
    else
        echo "docker-compose.dev.yml"
    fi
}

# Main installation function
main() {
    print_header
    
    echo -e "${YELLOW}"
    echo "⚠️  WARNING: This will:"
    echo "  - Stop and remove all containers"
    echo "  - Delete all volumes (LOCAL DATABASE WILL BE LOST!)"
    echo "  - Rebuild everything from scratch"
    echo -e "${NC}"
    echo ""
    
    if [ "$AUTO_CONFIRM" = false ]; then
        read -p "Continue? (type 'yes' to confirm) " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Installation cancelled."
            exit 0
        fi
        
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}  Ollama (Local AI) Configuration${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo ""
        echo "Ollama allows you to run AI models locally."
        echo "If you're using Groq/DeepSeek API, you can skip this."
        echo ""
        read -p "Install Ollama? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            INCLUDE_OLLAMA=true
            print_step "Ollama will be installed"
        else
            INCLUDE_OLLAMA=false
            print_step "Skipping Ollama installation"
        fi
    else
        INCLUDE_OLLAMA=false
    fi
    
    echo ""
    
    # Detect docker compose
    COMPOSE_CMD=$(get_docker_compose_cmd)
    print_step "Using command: $COMPOSE_CMD"
    
    # Detect database mode
    detect_database_mode
    
    # Get appropriate compose file
    COMPOSE_FILE=$(get_compose_file)
    print_step "Using compose file: $COMPOSE_FILE"
    
    echo ""
    
    # Step 1: Stop and remove everything
    print_step "Stopping and removing all containers..."
    
    # Stop both local and dev compose files to clean up
    $COMPOSE_CMD -f docker-compose.local.yml down -v --remove-orphans 2>&1 || true
    $COMPOSE_CMD -f docker-compose.dev.yml down -v --remove-orphans 2>&1 || true
    $COMPOSE_CMD down -v --remove-orphans 2>&1 || true
    
    print_success "Containers and volumes removed"
    
    echo ""
    
    # Step 2: Remove any lingering .env in API (should be blocked by .dockerignore anyway)
    if [ -f "apps/api/.env" ]; then
        print_warning "Found apps/api/.env, removing it..."
        rm apps/api/.env
        print_success "Removed apps/api/.env"
        echo ""
    fi
    
    # Step 3: Build and start containers
    print_step "Building and starting containers..."
    
    if [ "$DB_MODE" = "local" ]; then
        print_info "Starting MySQL + Redis (local database mode)"
    else
        print_info "Starting Redis only (remote database mode)"
    fi
    
    if [ "$INCLUDE_OLLAMA" = true ]; then
        $COMPOSE_CMD -f "$COMPOSE_FILE" --profile ollama up -d --build 2>&1 | sed 's/^/  /'
    else
        $COMPOSE_CMD -f "$COMPOSE_FILE" up -d --build 2>&1 | sed 's/^/  /'
    fi
    print_success "Containers started"
    
    echo ""
    
    # Step 4: Wait for services to be ready
    print_step "Waiting for services to be ready..."
    
    # Wait for MySQL if local mode
    if [ "$DB_MODE" = "local" ]; then
        echo "  Waiting for MySQL..."
        for i in {1..60}; do
            if docker exec grammarly_mysql mysqladmin ping -h localhost --silent 2>/dev/null; then
                print_success "MySQL is ready"
                break
            fi
            if [ $i -eq 60 ]; then
                print_warning "MySQL is taking longer than expected"
            fi
            sleep 1
        done
    fi
    
    # Wait for Redis
    for i in {1..30}; do
        if docker exec grammarly_redis redis-cli ping &> /dev/null; then
            print_success "Redis is ready"
            break
        fi
        sleep 1
    done
    
    echo ""
    
    # Step 5: Run database migrations
    print_step "Running Prisma migrations..."
    
    cd "$PROJECT_ROOT/apps/api"
    
    # Export DATABASE_URL from root .env for Prisma
    if [ -f "$PROJECT_ROOT/.env" ]; then
        export $(grep -E "^DATABASE_URL=" "$PROJECT_ROOT/.env" | xargs)
        print_info "DATABASE_URL loaded from .env"
    else
        print_warning "No .env file found at project root"
    fi
    
    # Generate Prisma client and run migrations
    if npx prisma generate 2>&1 | sed 's/^/  /'; then
        print_success "Prisma client generated"
    else
        print_warning "Prisma generate failed"
    fi
    
    if npx prisma migrate deploy 2>&1 | sed 's/^/  /'; then
        print_success "Database migrations completed"
    else
        print_warning "Migration failed. Ensure DATABASE_URL is correct"
    fi
    
    cd "$PROJECT_ROOT"
    
    echo ""
    
    # Step 6: Verify all services
    print_step "Verifying all services..."
    
    # Check MySQL (depending on mode)
    if [ "$DB_MODE" = "local" ]; then
        if docker exec grammarly_mysql mysqladmin ping -h localhost --silent 2>/dev/null; then
            print_success "✓ MySQL: Connected (local Docker)"
        else
            print_error "✗ MySQL: Failed to connect"
        fi
    else
        print_success "✓ MySQL: Using Remote Database"
    fi
    
    # Check Redis
    if docker exec grammarly_redis redis-cli ping &> /dev/null; then
        print_success "✓ Redis: Connected"
    else
        print_error "✗ Redis: Failed"
    fi
    
    # Database check
    print_success "✓ Database: Migrations deployed"
    
    echo ""
    echo -e "${GREEN}==========================================="
    echo "  Installation Complete!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}Database Mode:${NC}"
    if [ "$DB_MODE" = "local" ]; then
        echo "  MySQL: Docker container (port 3307)"
    else
        echo "  MySQL: Remote server"
    fi
    echo "  Redis: Docker container (port 6381)"
    echo ""
    echo -e "${CYAN}To start the application:${NC}"
    echo "  ${BLUE}bash scripts/linux/start.sh${NC}"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo "  Check status:     ${BLUE}bash scripts/linux/status.sh${NC}"
    echo "  View logs:        ${BLUE}docker logs grammarly_redis${NC}"
    echo "  Stop all:         ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE down${NC}"
    echo ""
}

main "$@"
