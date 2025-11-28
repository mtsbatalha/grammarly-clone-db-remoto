#!/bin/bash

# ===========================================
# Grammarly Clone - Start Script (Linux/Mac)
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

print_banner() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "     Grammarly Clone - Starting..."
    echo "==========================================="
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Check if Docker is running
check_docker() {
    print_step "Checking Docker..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi

    print_success "Docker is running"
}

# Start Docker services
start_docker() {
    print_step "Starting Docker services (PostgreSQL, Redis)..."

    cd "$PROJECT_ROOT"

    # Use docker compose (new) or docker-compose (legacy)
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    # Start only database services (dev mode)
    $DOCKER_COMPOSE -f docker-compose.dev.yml up -d

    print_success "Docker services started"
}

# Wait for services
wait_for_services() {
    print_step "Waiting for services to be ready..."

    # Wait for PostgreSQL
    for i in {1..30}; do
        if docker exec grammarly_postgres pg_isready -U postgres &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "PostgreSQL failed to start"
            exit 1
        fi
        sleep 1
    done

    # Wait for Redis
    for i in {1..30}; do
        if docker exec grammarly_redis redis-cli ping &> /dev/null; then
            print_success "Redis is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "Redis failed to start"
            exit 1
        fi
        sleep 1
    done
}

# Check environment
check_env() {
    print_step "Checking environment configuration..."

    if [ ! -f "$PROJECT_ROOT/apps/api/.env" ]; then
        print_error ".env file not found at apps/api/.env"
        echo "Run './scripts/setup-linux.sh' first or copy from .env.example"
        exit 1
    fi

    print_success "Environment configured"
}

# Start application
start_app() {
    print_step "Starting application..."

    cd "$PROJECT_ROOT"

    echo ""
    echo -e "${GREEN}==========================================="
    echo "  Application Starting!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo -e "  Web:  ${BLUE}http://localhost:5173${NC}"
    echo -e "  API:  ${BLUE}http://localhost:3003${NC}"
    echo ""
    echo -e "  Press ${YELLOW}Ctrl+C${NC} to stop"
    echo ""

    # Start the dev server
    npm run dev
}

# Main
main() {
    print_banner
    check_docker
    start_docker
    wait_for_services
    check_env
    start_app
}

main "$@"
