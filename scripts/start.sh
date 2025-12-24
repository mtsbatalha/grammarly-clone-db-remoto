#!/bin/bash

# ===========================================
# Grammarly Clone - Start Script (Linux/Mac)
# ===========================================
#
# Features:
#   - Automatic port conflict detection
#   - Port fallback system
#   - Environment variable support
#
# Usage:
#   ./start.sh              # Normal start with port checking
#   ./start.sh --auto       # Automatic mode (use fallback ports)
#   ./start.sh --help       # Show help
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

# ===========================================
# Default Port Configuration
# ===========================================
DEFAULT_POSTGRES_PORT=5434
DEFAULT_REDIS_PORT=6381
DEFAULT_API_PORT=3003
DEFAULT_WEB_PORT=5173

# Fallback ports (increment if default is in use)
POSTGRES_PORT=${POSTGRES_PORT:-$DEFAULT_POSTGRES_PORT}
REDIS_PORT=${REDIS_PORT:-$DEFAULT_REDIS_PORT}
API_PORT=${API_PORT:-$DEFAULT_API_PORT}
WEB_PORT=${WEB_PORT:-$DEFAULT_WEB_PORT}

# Automatic mode flag
AUTO_MODE=false

# ===========================================
# Parse Arguments
# ===========================================
parse_args() {
    for arg in "$@"; do
        case $arg in
            -y|--yes|--auto)
                AUTO_MODE=true
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
        esac
    done
}

show_help() {
    echo ""
    echo "Grammarly Clone - Start Script"
    echo ""
    echo "Usage: ./start.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes, --auto   Automatic mode (use fallback ports without asking)"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  POSTGRES_PORT=5434  PostgreSQL port"
    echo "  REDIS_PORT=6381     Redis port"
    echo "  API_PORT=3003       API server port"
    echo "  WEB_PORT=5173       Web frontend port"
    echo ""
}

# ===========================================
# Output Functions
# ===========================================
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

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# ===========================================
# Port Detection Functions
# ===========================================

# Check if a port is in use
is_port_in_use() {
    local port=$1
    if command -v ss &> /dev/null; then
        ss -tuln 2>/dev/null | grep -q ":$port "
    elif command -v netstat &> /dev/null; then
        netstat -tuln 2>/dev/null | grep -q ":$port "
    elif command -v lsof &> /dev/null; then
        lsof -i :$port -sTCP:LISTEN &> /dev/null
    else
        # Fallback: try to bind to the port
        (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null && return 0 || return 1
    fi
}

# Find next available port
find_available_port() {
    local start_port=$1
    local max_attempts=${2:-10}
    local port=$start_port

    for ((i=0; i<max_attempts; i++)); do
        if ! is_port_in_use $port; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done

    # No available port found
    echo ""
    return 1
}

# Get process using a port
get_port_process() {
    local port=$1
    if command -v lsof &> /dev/null; then
        lsof -i :$port -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1, "(PID:"$2")"}'
    elif command -v ss &> /dev/null; then
        ss -tlnp 2>/dev/null | grep ":$port " | sed 's/.*users:(("\([^"]*\)".*/\1/'
    else
        echo "unknown process"
    fi
}

# Check and handle port conflicts
check_port_conflicts() {
    print_step "Checking port availability..."
    
    local conflicts=()
    local port_changes=()

    # Check PostgreSQL port
    if is_port_in_use $POSTGRES_PORT; then
        local process=$(get_port_process $POSTGRES_PORT)
        print_warning "Port $POSTGRES_PORT (PostgreSQL) is in use by: $process"
        local new_port=$(find_available_port $((POSTGRES_PORT + 1)))
        if [ -n "$new_port" ]; then
            conflicts+=("PostgreSQL: $POSTGRES_PORT -> $new_port")
            port_changes+=("POSTGRES_PORT=$new_port")
            POSTGRES_PORT=$new_port
        else
            print_error "No available port found for PostgreSQL"
            exit 1
        fi
    fi

    # Check Redis port
    if is_port_in_use $REDIS_PORT; then
        local process=$(get_port_process $REDIS_PORT)
        print_warning "Port $REDIS_PORT (Redis) is in use by: $process"
        local new_port=$(find_available_port $((REDIS_PORT + 1)))
        if [ -n "$new_port" ]; then
            conflicts+=("Redis: $REDIS_PORT -> $new_port")
            port_changes+=("REDIS_PORT=$new_port")
            REDIS_PORT=$new_port
        else
            print_error "No available port found for Redis"
            exit 1
        fi
    fi

    # Check API port
    if is_port_in_use $API_PORT; then
        local process=$(get_port_process $API_PORT)
        print_warning "Port $API_PORT (API) is in use by: $process"
        local new_port=$(find_available_port $((API_PORT + 1)))
        if [ -n "$new_port" ]; then
            conflicts+=("API: $API_PORT -> $new_port")
            port_changes+=("API_PORT=$new_port")
            API_PORT=$new_port
        else
            print_error "No available port found for API"
            exit 1
        fi
    fi

    # Check Web port
    if is_port_in_use $WEB_PORT; then
        local process=$(get_port_process $WEB_PORT)
        print_warning "Port $WEB_PORT (Web) is in use by: $process"
        local new_port=$(find_available_port $((WEB_PORT + 1)))
        if [ -n "$new_port" ]; then
            conflicts+=("Web: $WEB_PORT -> $new_port")
            port_changes+=("WEB_PORT=$new_port")
            WEB_PORT=$new_port
        else
            print_error "No available port found for Web"
            exit 1
        fi
    fi

    # If conflicts were found
    if [ ${#conflicts[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Port conflicts detected! Suggested fallback ports:${NC}"
        for conflict in "${conflicts[@]}"; do
            echo "  - $conflict"
        done
        echo ""

        if [ "$AUTO_MODE" = true ]; then
            print_step "Auto-mode: Using fallback ports"
        else
            read -p "Use these fallback ports? (Y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                echo ""
                echo "You can manually set ports via environment variables:"
                for change in "${port_changes[@]}"; do
                    echo "  export $change"
                done
                echo ""
                echo "Or stop the processes using these ports and try again."
                exit 0
            fi
        fi

        # Update docker-compose override or environment
        update_port_configuration
    else
        print_success "All ports are available"
    fi
}

# Update port configuration in docker-compose.override.yml
update_port_configuration() {
    print_step "Updating port configuration..."

    OVERRIDE_FILE="$PROJECT_ROOT/docker-compose.override.yml"

    cat > "$OVERRIDE_FILE" << EOF
# ===========================================
# Docker Compose Override - Auto-generated
# Generated due to port conflicts
# ===========================================
services:
  postgres:
    ports:
      - "${POSTGRES_PORT}:5432"

  redis:
    ports:
      - "${REDIS_PORT}:6379"
EOF

    print_success "Created docker-compose.override.yml with fallback ports"

    # Update API .env if it exists
    API_ENV="$PROJECT_ROOT/apps/api/.env"
    if [ -f "$API_ENV" ]; then
        # Update DATABASE_URL
        sed -i.bak "s|postgresql://postgres:postgres@localhost:[0-9]*/grammarly_clone|postgresql://postgres:postgres@localhost:${POSTGRES_PORT}/grammarly_clone|g" "$API_ENV"
        # Update REDIS_URL
        sed -i.bak "s|redis://localhost:[0-9]*|redis://localhost:${REDIS_PORT}|g" "$API_ENV"
        rm -f "$API_ENV.bak"
        print_success "Updated apps/api/.env with new ports"
    fi
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
    # Include override file if it exists
    if [ -f "docker-compose.override.yml" ]; then
        $DOCKER_COMPOSE -f docker-compose.dev.yml -f docker-compose.override.yml up -d
    else
        $DOCKER_COMPOSE -f docker-compose.dev.yml up -d
    fi

    print_success "Docker services started"
}

# Wait for services
wait_for_services() {
    print_step "Waiting for services to be ready..."

    # Wait for PostgreSQL
    for i in {1..30}; do
        if docker exec grammarly_postgres pg_isready -U postgres &> /dev/null; then
            print_success "PostgreSQL is ready (port $POSTGRES_PORT)"
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
            print_success "Redis is ready (port $REDIS_PORT)"
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
    echo -e "  Web:  ${BLUE}http://localhost:${WEB_PORT}${NC}"
    echo -e "  API:  ${BLUE}http://localhost:${API_PORT}${NC}"
    echo ""
    echo -e "  Database Ports:"
    echo -e "    PostgreSQL: ${BLUE}localhost:${POSTGRES_PORT}${NC}"
    echo -e "    Redis:      ${BLUE}localhost:${REDIS_PORT}${NC}"
    echo ""
    echo -e "  Press ${YELLOW}Ctrl+C${NC} to stop"
    echo ""

    # Export ports for npm scripts
    export PORT=$API_PORT
    export VITE_PORT=$WEB_PORT

    # Start the dev server
    npm run dev
}

# Main
main() {
    parse_args "$@"
    print_banner
    check_docker
    check_port_conflicts
    start_docker
    wait_for_services
    check_env
    start_app
}

main "$@"
