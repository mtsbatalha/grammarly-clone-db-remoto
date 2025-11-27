#!/bin/bash

# ===========================================
# Grammarly Clone - Kill Node.js Processes
# ===========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (matching docker-compose.yml)
API_PORT=${API_PORT:-3003}
WEB_PORT=${WEB_PORT:-5173}

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

# Kill process on specific port (cross-platform compatible)
kill_port_process() {
    local port=$1
    local port_name=$2
    
    print_step "Checking for processes on port $port ($port_name)..."
    
    # Try to find and kill process using lsof (Linux/macOS)
    if command -v lsof &> /dev/null; then
        local pids=$(lsof -ti :$port 2>/dev/null || echo "")
        if [ -n "$pids" ]; then
            print_warning "Found process(es) on port $port: $pids"
            echo "$pids" | xargs -r kill -9 2>/dev/null || true
            print_success "Killed process on port $port"
            sleep 1
        else
            print_step "No process found on port $port"
        fi
    # Fallback: try ss (systemd-based systems)
    elif command -v ss &> /dev/null; then
        local pid=$(ss -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d',' -f2 | head -1 || echo "")
        if [ -n "$pid" ] && [ "$pid" != "-" ]; then
            print_warning "Found process on port $port (PID: $pid)"
            kill -9 "$pid" 2>/dev/null || true
            print_success "Killed process on port $port"
            sleep 1
        else
            print_step "No process found on port $port"
        fi
    # Fallback: try fuser
    elif command -v fuser &> /dev/null; then
        if fuser $port/tcp &> /dev/null; then
            print_warning "Found process on port $port"
            fuser -k $port/tcp 2>/dev/null || true
            print_success "Killed process on port $port"
            sleep 1
        else
            print_step "No process found on port $port"
        fi
    else
        print_warning "Cannot find port killer tool (lsof, ss, or fuser). Please install one."
        return 1
    fi
}

# Main function
main() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  Killing Node.js Processes"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo "This script will kill any processes running on:"
    echo "  - API port:  $API_PORT"
    echo "  - Web port:  $WEB_PORT"
    echo ""
    
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo ""
    
    # Kill processes on both ports
    kill_port_process "$API_PORT" "API"
    kill_port_process "$WEB_PORT" "Web"
    
    echo ""
    echo -e "${GREEN}==========================================="
    echo "  All Node.js processes killed!"
    echo "==========================================="
    echo -e "${NC}"
}

# Run main function
main "$@"
