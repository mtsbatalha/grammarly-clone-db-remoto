#!/bin/bash

# ===========================================
# Grammarly Clone - Restart Docker Containers
# ===========================================
#
# Usage:
#   ./restart-containers.sh         # Restart main services only
#   ./restart-containers.sh --all   # Restart all services including NGINX Proxy Manager
#   ./restart-containers.sh --npm   # Restart NGINX Proxy Manager only
#

set -e

# Parse arguments
RESTART_ALL=false
RESTART_NPM_ONLY=false
RESET_PORTS=false

for arg in "$@"; do
    case $arg in
        --all|-a)
            RESTART_ALL=true
            ;;
        --npm|-n)
            RESTART_NPM_ONLY=true
            ;;
        --reset-ports|-r)
            RESET_PORTS=true
            ;;
    esac
done

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

# Restart NGINX Proxy Manager
restart_npm() {
    print_step "Stopping NGINX Proxy Manager..."
    $DOCKER_COMPOSE -f docker-compose.npm.yml down 2>&1 || true

    print_step "Starting NGINX Proxy Manager..."
    $DOCKER_COMPOSE -f docker-compose.npm.yml up -d

    # Wait for NPM to be ready
    print_step "Waiting for NGINX Proxy Manager..."
    for i in {1..30}; do
        if curl -s http://localhost:81 > /dev/null 2>&1; then
            print_success "NGINX Proxy Manager is ready"
            break
        fi
        echo "Waiting for NPM... ($i/30)"
        sleep 2
    done
}

# Restart main services
restart_main() {
    # Check for override file
    OVERRIDE_ARGS=""
    if [ -f "docker-compose.override.yml" ]; then
        OVERRIDE_ARGS="-f docker-compose.override.yml"
        print_step "Using port override configuration"
    fi

    # Reset ports if requested
    if [ "$RESET_PORTS" = true ] && [ -f "docker-compose.override.yml" ]; then
        print_step "Removing port override file..."
        rm -f "docker-compose.override.yml"
        OVERRIDE_ARGS=""
        print_success "Ports reset to defaults"
    fi

    # Stop containers
    print_step "Stopping main containers..."
    $DOCKER_COMPOSE $OVERRIDE_ARGS down 2>&1 || true
    print_success "Containers stopped"

    echo ""

    # Remove orphan containers
    print_step "Cleaning up orphaned containers..."
    $DOCKER_COMPOSE $OVERRIDE_ARGS down --remove-orphans 2>&1 || true
    print_success "Cleanup complete"

    echo ""

    # Start containers again
    print_step "Starting containers..."
    $DOCKER_COMPOSE $OVERRIDE_ARGS up -d
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
}

# Main function
main() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  Restarting Docker Containers"
    echo "==========================================="
    echo -e "${NC}"

    if $RESTART_NPM_ONLY; then
        echo "Mode: NGINX Proxy Manager only"
    elif $RESTART_ALL; then
        echo "Mode: All services (including NGINX Proxy Manager)"
    else
        echo "Mode: Main services only"
        echo "  Use --all to include NGINX Proxy Manager"
        echo "  Use --npm to restart only NGINX Proxy Manager"
        echo "  Use --reset-ports to reset to default ports"
    fi

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

    # Restart based on mode
    if $RESTART_NPM_ONLY; then
        restart_npm
    elif $RESTART_ALL; then
        restart_main
        echo ""
        restart_npm
    else
        restart_main
    fi

    echo ""
    echo -e "${GREEN}==========================================="
    echo "  All containers restarted successfully!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo "Services status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Run main function
main "$@"
