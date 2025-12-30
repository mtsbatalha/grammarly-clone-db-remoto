#!/bin/bash

# ===========================================
# Grammarly Clone - Fresh Install Script
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
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || exit 1

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

print_header() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  Grammarly Clone - Fresh Install"
    echo "==========================================="
    echo -e "${NC}"
}

# Detect docker compose command
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

# Main installation function
main() {
    print_header
    
    echo -e "${YELLOW}"
    echo "⚠️  WARNING: This will:"
    echo "  - Stop and remove all containers"
    echo "  - Delete all volumes (DATABASE WILL BE LOST!)"
    echo "  - Rebuild everything from scratch"
    echo -e "${NC}"
    echo ""
    
    if [ "$AUTO_CONFIRM" = false ]; then
        read -p "Continue? (type 'yes' to confirm) " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi
    
    echo ""
    
    # Detect docker compose
    COMPOSE_CMD=$(get_docker_compose_cmd)
    print_step "Using command: $COMPOSE_CMD"
    
    # Step 1: Stop and remove everything
    print_step "Stopping and removing all containers..."
    $COMPOSE_CMD down -v --remove-orphans 2>&1 | sed 's/^/  /'
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
    $COMPOSE_CMD up -d --build 2>&1 | sed 's/^/  /'
    print_success "Containers started"
    
    echo ""
    
    # Step 4: Wait for PostgreSQL to be ready
    print_step "Waiting for PostgreSQL to be ready..."
    for i in {1..30}; do
        if docker exec grammarly_postgres pg_isready -U postgres &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        echo "  Waiting... ($i/30)"
        sleep 2
    done
    
    # Extra wait for full readiness
    sleep 3
    
    echo ""
    
    # Step 5: Run database migrations
    print_step "Running Prisma migrations..."
    if docker exec grammarly_api npx prisma migrate deploy 2>&1 | sed 's/^/  /'; then
        print_success "Database migrations completed"
    else
        print_warning "Migration failed, trying reset..."
        docker exec grammarly_api npx prisma migrate reset --force 2>&1 | sed 's/^/  /'
        print_success "Database reset completed"
    fi
    
    echo ""
    
    # Step 6: Wait for API to be healthy
    print_step "Waiting for API to be healthy..."
    for i in {1..30}; do
        if docker logs grammarly_api 2>&1 | grep -q "Server running on"; then
            print_success "API is running"
            break
        fi
        echo "  Waiting for API... ($i/30)"
        sleep 2
    done
    
    echo ""
    
    # Step 7: Verify all services
    print_step "Verifying all services..."
    
    # Check PostgreSQL
    if docker exec grammarly_postgres psql -U postgres -d grammarly_clone -c "SELECT 1" &> /dev/null; then
        print_success "✓ PostgreSQL: Connected"
    else
        print_error "✗ PostgreSQL: Failed"
    fi
    
    # Check Redis
    if docker exec grammarly_redis redis-cli ping &> /dev/null; then
        print_success "✓ Redis: Connected"
    else
        print_error "✗ Redis: Failed"
    fi
    
    # Check API health
    if curl -s http://localhost:3002/health | grep -q "healthy"; then
        print_success "✓ API: Healthy"
    else
        print_warning "✗ API: Not responding (check logs)"
    fi
    
    # Check tables exist
    table_count=$(docker exec grammarly_postgres psql -U postgres -d grammarly_clone -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
    if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
        print_success "✓ Database: $table_count tables created"
    else
        print_error "✗ Database: No tables found"
    fi
    
    echo ""
    echo -e "${GREEN}==========================================="
    echo "  Installation Complete!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo -e "${CYAN}Access your application:${NC}"
    echo "  🌐 Web Interface: ${BLUE}http://localhost:5173${NC}"
    echo "  🔌 API Server:    ${BLUE}http://localhost:3002${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Open http://localhost:5173 in your browser"
    echo "  2. Register a new user account"
    echo "  3. Start using Grammarly Clone!"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo "  Check status:     ${BLUE}bash scripts/status.sh${NC}"
    echo "  View logs:        ${BLUE}docker logs grammarly_api${NC}"
    echo "  Stop all:         ${BLUE}$COMPOSE_CMD down${NC}"
    echo "  Restart:          ${BLUE}bash scripts/restart-containers.sh${NC}"
    echo ""
}

main "$@"
