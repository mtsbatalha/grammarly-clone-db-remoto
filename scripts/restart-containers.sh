#!/bin/bash

# ===========================================
# Grammarly Clone - Restart Docker Containers
# ===========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Get project root directory with fallback
get_project_root() {
    if [ -n "${BASH_SOURCE[0]}" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    else
        SCRIPT_DIR="$(pwd)"
    fi
    
    if [ ! -d "$SCRIPT_DIR" ]; then
        SCRIPT_DIR="$(pwd)"
    fi
    
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    
    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        print_error "Could not find project root. Expected docker-compose.yml at $PROJECT_ROOT"
        return 1
    fi
    
    echo "$PROJECT_ROOT"
}

# Main function
main() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  Restarting Docker Containers"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo "This script will:"
    echo "  1. Stop all running containers"
    echo "  2. Remove stopped containers"
    echo "  3. Start containers again"
    echo ""
    
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo ""
    
    # Get project root
    PROJECT_ROOT=$(get_project_root) || exit 1
    
    cd "$PROJECT_ROOT" || exit 1
    
    # Determine docker compose command
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi
    
    # Stop containers
    print_step "Stopping containers..."
    $DOCKER_COMPOSE down 2>&1 || true
    print_success "Containers stopped"
    
    echo ""
    
    # Remove orphan containers
    print_step "Cleaning up orphaned containers..."
    $DOCKER_COMPOSE down --remove-orphans 2>&1 || true
    print_success "Cleanup complete"
    
    echo ""
    
    # Start containers again
    print_step "Starting containers..."
    $DOCKER_COMPOSE up -d
    print_success "Containers started"
    
    echo ""
    
    # Wait for services
    print_step "Waiting for services to be ready..."
    sleep 3
    
    # Check PostgreSQL
    POSTGRES_CONTAINER="grammarly_postgres"
    for i in {1..30}; do
        if docker exec $POSTGRES_CONTAINER pg_isready -U postgres &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        echo "Waiting for PostgreSQL... ($i/30)"
        sleep 2
    done
    
    # Check Redis
    REDIS_CONTAINER="grammarly_redis"
    for i in {1..30}; do
        if docker exec $REDIS_CONTAINER redis-cli ping &> /dev/null; then
            print_success "Redis is ready"
            break
        fi
        echo "Waiting for Redis... ($i/30)"
        sleep 2
    done
    
    echo ""
    echo -e "${GREEN}==========================================="
    echo "  All containers restarted successfully!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo "Services status:"
    $DOCKER_COMPOSE ps
}

# Run main function
main "$@"
