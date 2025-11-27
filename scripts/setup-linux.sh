#!/bin/bash

# ===========================================
# Grammarly Clone - Linux Setup Script
# Compatible with Debian 12/13, Ubuntu 22.04+
# ===========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (matching docker-compose.yml)
POSTGRES_PORT=${POSTGRES_PORT:-5434}
REDIS_PORT=${REDIS_PORT:-6381}
API_PORT=${API_PORT:-3003}
WEB_PORT=${WEB_PORT:-5173}

# Container names (matching docker-compose.yml)
POSTGRES_CONTAINER="grammarly_postgres"
REDIS_CONTAINER="grammarly_redis"

print_header() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "  Grammarly Clone - Setup Script"
    echo "==========================================="
    echo -e "${NC}"
}

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

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. Some operations will be performed without sudo."
        SUDO=""
    else
        SUDO="sudo"
    fi
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="$SUDO apt-get update"
        PKG_INSTALL="$SUDO apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="$SUDO dnf check-update || true"
        PKG_INSTALL="$SUDO dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="$SUDO yum check-update || true"
        PKG_INSTALL="$SUDO yum install -y"
    else
        print_error "No supported package manager found (apt-get, dnf, yum)"
        exit 1
    fi
    print_step "Detected package manager: $PKG_MANAGER"
}

# Install system dependencies
install_system_deps() {
    print_step "Installing system dependencies..."

    $PKG_UPDATE

    # Install basic dependencies
    $PKG_INSTALL curl wget git build-essential

    print_success "System dependencies installed"
}

# Install Node.js (via nvm for better version control)
install_nodejs() {
    print_step "Checking Node.js installation..."

    if command -v node &> /dev/null; then
        NODE_VERSION=$(node -v)
        print_step "Node.js already installed: $NODE_VERSION"

        # Check if version is >= 18
        MAJOR_VERSION=$(echo $NODE_VERSION | cut -d'.' -f1 | tr -d 'v')
        if [ "$MAJOR_VERSION" -lt 18 ]; then
            print_warning "Node.js version is less than 18. Installing newer version..."
        else
            return 0
        fi
    fi

    print_step "Installing Node.js 20.x..."

    if [ "$PKG_MANAGER" = "apt-get" ]; then
        # Install Node.js via NodeSource
        curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
        $PKG_INSTALL nodejs
    else
        # Install via nvm for other distros
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install 20
        nvm use 20
    fi

    print_success "Node.js installed: $(node -v)"
}

# Install Docker and Docker Compose
install_docker() {
    print_step "Checking Docker installation..."

    if command -v docker &> /dev/null; then
        print_step "Docker already installed: $(docker --version)"
    else
        print_step "Installing Docker..."

        if [ "$PKG_MANAGER" = "apt-get" ]; then
            # Install Docker via official script
            curl -fsSL https://get.docker.com | $SUDO sh

            # Add current user to docker group
            $SUDO usermod -aG docker $USER
            print_warning "You may need to log out and back in for docker group changes to take effect"
        else
            $PKG_INSTALL docker docker-compose
            $SUDO systemctl enable docker
            $SUDO systemctl start docker
        fi

        print_success "Docker installed"
    fi

    # Check Docker Compose
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_step "Docker Compose already available"
    else
        print_step "Installing Docker Compose..."
        $SUDO curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        $SUDO chmod +x /usr/local/bin/docker-compose
        print_success "Docker Compose installed"
    fi
}

# Setup project
setup_project() {
    print_step "Setting up project..."

    # Get project root directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    cd "$PROJECT_ROOT"

    # Install npm dependencies
    print_step "Installing npm dependencies..."
    npm install

    print_success "Project dependencies installed"
}

# Create environment file
create_env_file() {
    print_step "Creating environment configuration..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    ENV_FILE="$PROJECT_ROOT/apps/api/.env"

    # Generate random JWT secret
    JWT_SECRET=$(openssl rand -hex 32)

    # Check if .env already exists
    if [ -f "$ENV_FILE" ]; then
        print_warning ".env file already exists. Creating backup..."
        cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # Prompt for Groq API key
    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  Groq API Key Configuration${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo "To use AI features, you need a Groq API key."
    echo "Get your free API key at: https://console.groq.com"
    echo ""
    read -p "Enter your Groq API key (or press Enter to skip): " GROQ_API_KEY

    cat > "$ENV_FILE" << EOF
# Server
NODE_ENV=development
PORT=$API_PORT

# Database (Docker)
DATABASE_URL=postgresql://postgres:postgres@localhost:$POSTGRES_PORT/grammarly_clone

# Redis (Docker)
REDIS_URL=redis://localhost:$REDIS_PORT

# JWT
JWT_SECRET=$JWT_SECRET
JWT_EXPIRES_IN=7d
JWT_REFRESH_EXPIRES_IN=30d

# AI Provider
AI_PROVIDER=groq
GROQ_API_KEY=$GROQ_API_KEY

# CORS
CORS_ORIGIN=http://localhost:$WEB_PORT

# Logging
LOG_LEVEL=info
EOF

    print_success "Environment file created at $ENV_FILE"
}

# Start Docker services
start_docker_services() {
    print_step "Starting Docker services (PostgreSQL, Redis)..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    cd "$PROJECT_ROOT"

    # Use docker compose (new) or docker-compose (legacy)
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi

    $DOCKER_COMPOSE up -d

    # Wait for services to be ready
    print_step "Waiting for services to be ready..."
    sleep 5

    # Check if PostgreSQL is ready
    for i in {1..30}; do
        if docker exec $POSTGRES_CONTAINER pg_isready -U postgres &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        echo "Waiting for PostgreSQL... ($i/30)"
        sleep 2
    done

    # Check if Redis is ready
    for i in {1..30}; do
        if docker exec $REDIS_CONTAINER redis-cli ping &> /dev/null; then
            print_success "Redis is ready"
            break
        fi
        echo "Waiting for Redis... ($i/30)"
        sleep 2
    done
}

# Setup database
setup_database() {
    print_step "Setting up database..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    cd "$PROJECT_ROOT/apps/api"

    # Run Prisma migrations
    print_step "Running database migrations..."
    npx prisma generate
    npx prisma db push

    print_success "Database setup complete"
}

# Build project
build_project() {
    print_step "Building project..."

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

    cd "$PROJECT_ROOT"

    npm run build

    print_success "Project built successfully"
}

# Print final instructions
print_final_instructions() {
    echo ""
    echo -e "${GREEN}==========================================="
    echo "  Setup Complete!"
    echo "==========================================="
    echo -e "${NC}"
    echo ""
    echo "To start the application:"
    echo ""
    echo "  1. Start all services:"
    echo -e "     ${BLUE}npm run dev${NC}"
    echo ""
    echo "  2. Or start individually:"
    echo -e "     ${BLUE}npm run dev:api${NC}    - Start API server"
    echo -e "     ${BLUE}npm run dev:web${NC}    - Start web frontend"
    echo ""
    echo "Access the application:"
    echo -e "  - Web Interface: ${BLUE}http://localhost:$WEB_PORT${NC}"
    echo -e "  - API:           ${BLUE}http://localhost:$API_PORT${NC}"
    echo ""
    echo "Docker services:"
    echo -e "  - PostgreSQL:    ${BLUE}localhost:$POSTGRES_PORT${NC}"
    echo -e "  - Redis:         ${BLUE}localhost:$REDIS_PORT${NC}"
    echo ""
    echo "Useful commands:"
    echo -e "  ${BLUE}docker compose logs -f${NC}     - View service logs"
    echo -e "  ${BLUE}docker compose down${NC}        - Stop services"
    echo -e "  ${BLUE}docker compose up -d${NC}       - Start services"
    echo ""

    if [ -z "$GROQ_API_KEY" ]; then
        echo -e "${YELLOW}[NOTE]${NC} You haven't configured a Groq API key."
        echo "AI features won't work until you add your key to:"
        echo "$PROJECT_ROOT/apps/api/.env"
        echo ""
    fi
}

# Main installation flow
main() {
    print_header

    check_root
    detect_package_manager

    echo ""
    echo "This script will install and configure:"
    echo "  - Node.js 20.x"
    echo "  - Docker and Docker Compose"
    echo "  - PostgreSQL (via Docker)"
    echo "  - Redis (via Docker)"
    echo "  - Project dependencies"
    echo ""
    read -p "Continue with installation? (y/N) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi

    install_system_deps
    install_nodejs
    install_docker
    setup_project
    create_env_file
    start_docker_services
    setup_database
    build_project
    print_final_instructions
}

# Run main function
main "$@"
