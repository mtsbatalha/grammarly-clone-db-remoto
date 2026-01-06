#!/bin/bash

# ===========================================
# Grammarly Clone - Restart Docker Containers
# ===========================================
#
# Usage:
#   ./restart-containers.sh              # Restart all services
#   ./restart-containers.sh --reset-ports # Reset to default ports
#

set -e

# Parse arguments
RESET_PORTS=false

for arg in "$@"; do
    case $arg in
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
    
    # Check API health
    print_step "Checking API connection to database..."
    API_CONTAINER="grammarly_api"
    for i in {1..30}; do
        if docker logs $API_CONTAINER 2>&1 | grep -q "Server running on"; then
            print_success "API is ready and connected to database"
            break
        elif docker logs $API_CONTAINER 2>&1 | grep -q "Authentication failed"; then
            print_error "API failed to connect to database"
            print_warning "Check database credentials in apps/api/.env"
            break
        fi
        echo "Waiting for API... ($i/30)"
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

    if $RESET_PORTS; then
        echo "Mode: All services (resetting ports)"
    else
        echo "Mode: All services"
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

    # Restart services
    restart_main

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
