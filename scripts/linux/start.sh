#!/bin/bash

# ===========================================
# Grammarly Clone - Start Script (Linux/Mac)
# ===========================================
#
# Features:
#   - Automatic detection of remote vs local database
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
CYAN='\033[0;36m'
NC='\033[0m'

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# ===========================================
# Default Port Configuration
# ===========================================
DEFAULT_MYSQL_PORT=3307
DEFAULT_REDIS_PORT=6381
DEFAULT_API_PORT=3002
DEFAULT_WEB_PORT=5173

# Fallback ports (increment if default is in use)
MYSQL_PORT=${MYSQL_PORT:-$DEFAULT_MYSQL_PORT}
REDIS_PORT=${REDIS_PORT:-$DEFAULT_REDIS_PORT}
API_PORT=${API_PORT:-$DEFAULT_API_PORT}
WEB_PORT=${WEB_PORT:-$DEFAULT_WEB_PORT}

# Automatic mode flag
AUTO_MODE=false

# Database mode (local or remote)
DB_MODE="unknown"

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
    echo "  DATABASE_URL        MySQL connection string (auto-detected)"
    echo "  MYSQL_PORT=3307     MySQL port (local only)"
    echo "  REDIS_PORT=6381     Redis port"
    echo "  API_PORT=3002       API server port"
    echo "  WEB_PORT=5173       Web frontend port"
    echo ""
    echo "Database Detection:"
    echo "  The script automatically detects if DATABASE_URL points to:"
    echo "  - Local: localhost, 127.0.0.1, or no host specified"
    echo "  - Remote: Any other hostname"
    echo ""
    echo "  If LOCAL: MySQL will be started via Docker"
    echo "  If REMOTE: Only Redis will be started via Docker"
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

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# ===========================================
# Database Detection Functions
# ===========================================

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
    
    # Also check environment variable
    if [ -z "$DATABASE_URL" ] && [ -n "${DATABASE_URL:-}" ]; then
        DATABASE_URL="$DATABASE_URL"
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
        print_info "  Host: $DB_HOST"
    else
        DB_MODE="remote"
        print_success "Database mode: REMOTE"
        print_info "  Host: $DB_HOST"
    fi
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

    # Check MySQL port (only if local mode)
    if [ "$DB_MODE" = "local" ]; then
        if is_port_in_use $MYSQL_PORT; then
            local process=$(get_port_process $MYSQL_PORT)
            print_warning "Port $MYSQL_PORT (MySQL) is in use by: $process"
            local new_port=$(find_available_port $((MYSQL_PORT + 1)))
            if [ -n "$new_port" ]; then
                conflicts+=("MySQL: $MYSQL_PORT -> $new_port")
                port_changes+=("MYSQL_PORT=$new_port")
                MYSQL_PORT=$new_port
            else
                print_error "No available port found for MySQL"
                exit 1
            fi
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
    else
        print_success "All ports are available"
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
    print_step "Starting Docker services..."

    cd "$PROJECT_ROOT"

    # Use docker compose (new) or docker-compose (legacy)
    if docker compose version &> /dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    # Select the appropriate compose file based on DB mode
    if [ "$DB_MODE" = "local" ]; then
        echo -e "  ${CYAN}Mode: LOCAL${NC} - Starting MySQL + Redis"
        COMPOSE_FILE="docker-compose.local.yml"
    else
        echo -e "  ${CYAN}Mode: REMOTE${NC} - Starting Redis only (MySQL is remote)"
        COMPOSE_FILE="docker-compose.dev.yml"
    fi

    # Check if compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Compose file not found: $COMPOSE_FILE"
        print_info "Please ensure the file exists or run setup.sh first"
        exit 1
    fi

    $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d

    print_success "Docker services started"
}

# Wait for services
wait_for_services() {
    print_step "Waiting for services to be ready..."

    # Wait for MySQL (only if local mode)
    if [ "$DB_MODE" = "local" ]; then
        echo "  Waiting for MySQL..."
        for i in {1..60}; do
            if docker exec grammarly_mysql mysqladmin ping -h localhost --silent 2>/dev/null; then
                print_success "MySQL is ready (port $MYSQL_PORT)"
                break
            fi
            if [ $i -eq 60 ]; then
                print_warning "MySQL is taking longer than expected. Check docker logs grammarly_mysql"
            fi
            sleep 1
        done
    else
        print_info "MySQL: Using remote database"
    fi

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

    if [ ! -f "$PROJECT_ROOT/.env" ] && [ ! -f "$PROJECT_ROOT/apps/api/.env" ]; then
        print_warning ".env file not found"
        echo "  Creating default .env from .env.example..."
        if [ -f "$PROJECT_ROOT/.env.example" ]; then
            cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
            print_success "Created .env from .env.example"
        else
            print_error "No .env.example found. Please create .env manually."
            exit 1
        fi
    else
        print_success "Environment configured"
    fi
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
    echo -e "  Database Connection:"
    if [ "$DB_MODE" = "local" ]; then
        echo -e "    MySQL:      ${BLUE}localhost:${MYSQL_PORT}${NC} (Docker)"
    else
        echo -e "    MySQL:      ${BLUE}Remote Server${NC}"
    fi
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
    detect_database_mode
    check_port_conflicts
    start_docker
    wait_for_services
    check_env
    start_app
}

main "$@"
