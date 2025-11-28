#!/bin/bash

# ===========================================
# NGINX Proxy Manager - Installation Script
# ===========================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NPM_HTTP_PORT=${NPM_HTTP_PORT:-80}
NPM_HTTPS_PORT=${NPM_HTTPS_PORT:-443}
NPM_ADMIN_PORT=${NPM_ADMIN_PORT:-81}

print_banner() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  NGINX Proxy Manager - Setup"
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

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        SUDO=""
    else
        SUDO="sudo"
    fi
}

# Check Docker
check_docker() {
    print_step "Checking Docker..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker."
        exit 1
    fi

    print_success "Docker is running"
}

# Check if ports are available
check_ports() {
    print_step "Checking port availability..."

    local ports_in_use=""

    for port in $NPM_HTTP_PORT $NPM_HTTPS_PORT $NPM_ADMIN_PORT; do
        if $SUDO lsof -i :$port &> /dev/null || $SUDO netstat -tuln 2>/dev/null | grep -q ":$port "; then
            ports_in_use="$ports_in_use $port"
        fi
    done

    if [ -n "$ports_in_use" ]; then
        print_warning "The following ports are already in use:$ports_in_use"
        echo ""
        echo "You can change ports by setting environment variables:"
        echo "  NPM_HTTP_PORT=8080 NPM_HTTPS_PORT=8443 NPM_ADMIN_PORT=8181 ./setup-nginx-proxy.sh"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "All ports available ($NPM_HTTP_PORT, $NPM_HTTPS_PORT, $NPM_ADMIN_PORT)"
    fi
}

# Get project root
get_project_root() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
}

# Create docker-compose file for NPM
create_npm_compose() {
    print_step "Creating NGINX Proxy Manager configuration..."

    get_project_root

    mkdir -p "$PROJECT_ROOT/nginx-proxy-manager/data"
    mkdir -p "$PROJECT_ROOT/nginx-proxy-manager/letsencrypt"

    cat > "$PROJECT_ROOT/docker-compose.npm.yml" << EOF
# ===========================================
# NGINX Proxy Manager
# ===========================================
# Access admin panel at: http://localhost:${NPM_ADMIN_PORT}
# Default credentials:
#   Email:    admin@example.com
#   Password: changeme
# ===========================================

services:
  nginx-proxy-manager:
    image: 'jc21/nginx-proxy-manager:latest'
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - '${NPM_HTTP_PORT}:80'      # HTTP
      - '${NPM_HTTPS_PORT}:443'    # HTTPS
      - '${NPM_ADMIN_PORT}:81'     # Admin Panel
    volumes:
      - ./nginx-proxy-manager/data:/data
      - ./nginx-proxy-manager/letsencrypt:/etc/letsencrypt
    environment:
      - TZ=America/Sao_Paulo
    networks:
      - grammarly_network
      - npm_network

networks:
  grammarly_network:
    external: true
  npm_network:
    driver: bridge
EOF

    print_success "Configuration created"
}

# Create the grammarly network if it doesn't exist
create_network() {
    print_step "Creating Docker network..."

    if ! docker network inspect grammarly_network &> /dev/null; then
        docker network create grammarly_network
        print_success "Network 'grammarly_network' created"
    else
        print_success "Network 'grammarly_network' already exists"
    fi
}

# Start NGINX Proxy Manager
start_npm() {
    print_step "Starting NGINX Proxy Manager..."

    get_project_root
    cd "$PROJECT_ROOT"

    docker-compose -f docker-compose.npm.yml up -d

    print_success "NGINX Proxy Manager started"
}

# Wait for NPM to be ready
wait_for_npm() {
    print_step "Waiting for NGINX Proxy Manager to be ready..."

    for i in {1..60}; do
        if curl -s http://localhost:$NPM_ADMIN_PORT/api/ &> /dev/null; then
            print_success "NGINX Proxy Manager is ready"
            return 0
        fi
        sleep 2
    done

    print_warning "NGINX Proxy Manager may still be starting. Check logs with: docker logs nginx-proxy-manager"
}

# Print instructions
print_instructions() {
    echo ""
    echo -e "${GREEN}==========================================="
    echo "  NGINX Proxy Manager Installed!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo "Admin Panel:"
    echo -e "  URL:      ${BLUE}http://localhost:${NPM_ADMIN_PORT}${NC}"
    echo ""
    echo "Default Login:"
    echo -e "  Email:    ${YELLOW}admin@example.com${NC}"
    echo -e "  Password: ${YELLOW}changeme${NC}"
    echo ""
    echo -e "${RED}IMPORTANT: Change the default password immediately!${NC}"
    echo ""
    echo "Ports:"
    echo -e "  HTTP:   ${BLUE}${NPM_HTTP_PORT}${NC}"
    echo -e "  HTTPS:  ${BLUE}${NPM_HTTPS_PORT}${NC}"
    echo -e "  Admin:  ${BLUE}${NPM_ADMIN_PORT}${NC}"
    echo ""
    echo "To configure proxy for Grammarly Clone:"
    echo "  1. Open admin panel"
    echo "  2. Add Proxy Host"
    echo "  3. Domain: your-domain.com"
    echo "  4. Forward Hostname: grammarly_web (or host.docker.internal)"
    echo "  5. Forward Port: 5173 (web) or 3003 (api)"
    echo ""
    echo "Commands:"
    echo -e "  ${BLUE}docker-compose -f docker-compose.npm.yml logs -f${NC}  - View logs"
    echo -e "  ${BLUE}docker-compose -f docker-compose.npm.yml down${NC}     - Stop"
    echo -e "  ${BLUE}docker-compose -f docker-compose.npm.yml restart${NC}  - Restart"
    echo ""
}

# Add npm scripts to package.json helper
add_npm_scripts() {
    print_step "Adding npm scripts..."

    get_project_root

    # Check if jq is available
    if command -v jq &> /dev/null; then
        cd "$PROJECT_ROOT"

        # Add scripts using jq
        jq '.scripts["npm:up"] = "docker-compose -f docker-compose.npm.yml up -d"' package.json > tmp.json && mv tmp.json package.json
        jq '.scripts["npm:down"] = "docker-compose -f docker-compose.npm.yml down"' package.json > tmp.json && mv tmp.json package.json
        jq '.scripts["npm:logs"] = "docker-compose -f docker-compose.npm.yml logs -f"' package.json > tmp.json && mv tmp.json package.json

        print_success "Scripts added to package.json"
    else
        print_warning "jq not found. Add these scripts manually to package.json:"
        echo '  "npm:up": "docker-compose -f docker-compose.npm.yml up -d"'
        echo '  "npm:down": "docker-compose -f docker-compose.npm.yml down"'
        echo '  "npm:logs": "docker-compose -f docker-compose.npm.yml logs -f"'
    fi
}

# Main
main() {
    print_banner

    echo "This will install NGINX Proxy Manager for:"
    echo "  - Reverse proxy to your applications"
    echo "  - Free SSL certificates (Let's Encrypt)"
    echo "  - Easy domain management"
    echo ""
    echo "Ports to be used:"
    echo "  HTTP:  $NPM_HTTP_PORT"
    echo "  HTTPS: $NPM_HTTPS_PORT"
    echo "  Admin: $NPM_ADMIN_PORT"
    echo ""

    read -p "Continue? (Y/n) " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    check_root
    check_docker
    check_ports
    create_network
    create_npm_compose
    start_npm
    wait_for_npm
    add_npm_scripts
    print_instructions
}

main "$@"
