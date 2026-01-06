#!/bin/bash

# ===========================================
# Grammarly Clone - Linux Setup Script
# Compatible with Debian 12/13, Ubuntu 22.04+
# ===========================================
# 
# Usage: ./setup-linux.sh [OPTIONS]
# 
# Options:
#   -y, --yes, --auto    Run in automatic mode (no prompts, use defaults)
#   -d, --dir DIR        Set custom installation directory
#   -h, --help           Show this help message
#
# Examples:
#   ./setup-linux.sh                    # Interactive mode
#   ./setup-linux.sh -y                 # Automatic mode with defaults
#   ./setup-linux.sh -y -d /opt/myapp   # Automatic mode with custom directory
# ===========================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ===========================================
# Default Configuration
# ===========================================

# Installation mode (false = interactive, true = automatic)
AUTO_MODE=${AUTO_MODE:-false}

# Default installation directory
DEFAULT_INSTALL_DIR="/opt/grammarly-clone"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

# Configuration (matching docker-compose.yml)
POSTGRES_PORT=${POSTGRES_PORT:-5434}
REDIS_PORT=${REDIS_PORT:-6381}
API_PORT=${API_PORT:-3003}
WEB_PORT=${WEB_PORT:-5173}

# Container names (matching docker-compose.yml)
REDIS_CONTAINER="grammarly_remotedb_redis"
OLLAMA_CONTAINER="grammarly_remotedb_ollama"

# Default fallback values for automatic mode
DEFAULT_GROQ_API_KEY=""  # Empty by default, user can configure later
DEFAULT_JWT_SECRET=""    # Will be auto-generated if empty

# ===========================================
# Parse Command Line Arguments
# ===========================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes|--auto)
                AUTO_MODE=true
                shift
                ;;
            -d|--dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_warning "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Export for child processes
    export AUTO_MODE
    export INSTALL_DIR
}

show_help() {
    echo ""
    echo "Grammarly Clone - Linux Setup Script"
    echo ""
    echo "Usage: ./setup-linux.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes, --auto    Run in automatic mode (no prompts, use defaults)"
    echo "  -d, --dir DIR        Set custom installation directory (default: /opt/grammarly-clone)"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AUTO_MODE=true       Same as -y flag"
    echo "  INSTALL_DIR=/path    Same as -d flag"
    echo "  GROQ_API_KEY=key     Pre-set Groq API key"
    echo "  POSTGRES_PORT=5434   PostgreSQL port"
    echo "  REDIS_PORT=6381      Redis port"
    echo "  API_PORT=3003        API server port"
    echo "  WEB_PORT=5173        Web frontend port"
    echo ""
    echo "Examples:"
    echo "  # Interactive installation"
    echo "  ./setup-linux.sh"
    echo ""
    echo "  # Automatic installation with defaults"
    echo "  ./setup-linux.sh -y"
    echo ""
    echo "  # Automatic with custom directory"
    echo "  ./setup-linux.sh -y -d /opt/myapp"
    echo ""
    echo "  # Using environment variables"
    echo "  GROQ_API_KEY=gsk_xxx AUTO_MODE=true ./setup-linux.sh"
    echo ""
}

# ===========================================
# Helper function for prompts with fallback
# ===========================================
prompt_with_fallback() {
    local prompt_message="$1"
    local default_value="$2"
    local result=""

    if [ "$AUTO_MODE" = true ]; then
        # Automatic mode: use default value
        result="$default_value"
        if [ -n "$default_value" ]; then
            print_step "Auto-mode: Using default value for '$prompt_message'"
        else
            print_step "Auto-mode: Skipping prompt (empty default)"
        fi
    else
        # Interactive mode: ask user
        read -p "$prompt_message" result
        if [ -z "$result" ]; then
            result="$default_value"
        fi
    fi

    echo "$result"
}

# ===========================================
# Confirmation with fallback
# ===========================================
confirm_with_fallback() {
    local prompt_message="$1"
    local default_choice="${2:-y}"  # Default to yes

    if [ "$AUTO_MODE" = true ]; then
        # Automatic mode: use default choice
        print_step "Auto-mode: Auto-confirming '$prompt_message'"
        return 0
    else
        # Interactive mode: ask user
        read -p "$prompt_message (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]] || ([ -z "$REPLY" ] && [ "$default_choice" = "y" ]); then
            return 0
        else
            return 1
        fi
    fi
}

# Get the absolute path to the project root
get_project_root() {
    local script_path=""

    # Try to get the script's directory
    if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
        script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    elif [ -n "$0" ] && [ -f "$0" ]; then
        script_path="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    fi

    # If we found the script path, go up one level
    if [ -n "$script_path" ] && [ -d "$script_path" ]; then
        PROJECT_ROOT="$(cd "$script_path/.." 2>/dev/null && pwd)"
    fi

    # Verify we found the right directory
    if [ ! -f "$PROJECT_ROOT/package.json" ]; then
        # Try current directory
        if [ -f "$(pwd)/package.json" ]; then
            PROJECT_ROOT="$(pwd)"
        # Try parent of current directory
        elif [ -f "$(pwd)/../package.json" ]; then
            PROJECT_ROOT="$(cd "$(pwd)/.." && pwd)"
        # Try INSTALL_DIR
        elif [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/package.json" ]; then
            PROJECT_ROOT="$INSTALL_DIR"
        # Fallback: try default install directory
        elif [ -d "$DEFAULT_INSTALL_DIR" ] && [ -f "$DEFAULT_INSTALL_DIR/package.json" ]; then
            PROJECT_ROOT="$DEFAULT_INSTALL_DIR"
        # Legacy: try home directory
        elif [ -d "$HOME/grammarly-clone" ] && [ -f "$HOME/grammarly-clone/package.json" ]; then
            PROJECT_ROOT="$HOME/grammarly-clone"
        else
            print_error "Could not find project root. Please run this script from the project directory."
            print_error "Or clone the project first: git clone <repo> $INSTALL_DIR"
            exit 1
        fi
    fi

    export PROJECT_ROOT
    print_step "Project root: $PROJECT_ROOT"
}

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
        if [ -z "$SUDO" ]; then
            # Running as root, no need for sudo -E
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        else
            # Not root, use sudo -E to preserve environment
            curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO -E bash -
        fi
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

    cd "$PROJECT_ROOT" || return 1

    # Install npm dependencies
    print_step "Installing npm dependencies..."
    npm install

    print_success "Project dependencies installed"
}

# Create environment file
create_env_file() {
    print_step "Creating environment configuration..."

    ENV_FILE="$PROJECT_ROOT/apps/api/.env"

    if [ ! -d "$PROJECT_ROOT/apps/api" ]; then
        print_error "Could not find apps/api directory. Expected at $PROJECT_ROOT/apps/api"
        return 1
    fi

    # Generate random JWT secret
    JWT_SECRET=$(openssl rand -hex 32)

    # Check if .env already exists
    if [ -f "$ENV_FILE" ]; then
        print_warning ".env file already exists. Creating backup..."
        cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # Get Groq API key (from environment variable, prompt, or use default)
    if [ -n "${GROQ_API_KEY:-}" ]; then
        # Already set via environment variable
        print_step "Using pre-configured Groq API key from environment"
    elif [ "$AUTO_MODE" = true ]; then
        # Automatic mode: use empty default (can configure later)
        GROQ_API_KEY="$DEFAULT_GROQ_API_KEY"
        print_step "Auto-mode: Skipping Groq API key (configure later in .env)"
    else
        # Interactive mode: prompt user
        echo ""
        echo -e "${YELLOW}=========================================${NC}"
        echo -e "${YELLOW}  Groq API Key Configuration${NC}"
        echo -e "${YELLOW}=========================================${NC}"
        echo ""
        echo "To use AI features, you need a Groq API key."
        echo "Get your free API key at: https://console.groq.com"
        echo ""
        read -p "Enter your Groq API key (or press Enter to skip): " GROQ_API_KEY
        GROQ_API_KEY="${GROQ_API_KEY:-$DEFAULT_GROQ_API_KEY}"
    fi

    cat > "$ENV_FILE" << EOF
# Server
NODE_ENV=development
PORT=$API_PORT

# Database (Remote Neon DB)
DATABASE_URL=postgresql://neondb_owner:npg_GEtIZnPkM20N@ep-broad-term-af6syi55-pooler.c-2.us-west-2.aws.neon.tech/grammarly?sslmode=require

# Redis (Docker)
REDIS_URL=redis://localhost:6381

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
    
    if [ -z "$GROQ_API_KEY" ]; then
        print_warning "Groq API key not configured. Edit $ENV_FILE later to enable AI features."
    fi
}

# Start Docker services
start_docker_services() {
    print_step "Starting Docker services (Redis, Ollama)..."

    cd "$PROJECT_ROOT" || return 1

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

    # Local PostgreSQL wait removed (using remote Neon DB)

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

    cd "$PROJECT_ROOT/apps/api" || return 1

    # Run Prisma migrations
    print_step "Running database migrations on Remote DB..."
    npx prisma generate
    npx prisma migrate deploy

    print_success "Database migrations complete"
}

# Build project
build_project() {
    print_step "Building project..."

    cd "$PROJECT_ROOT" || return 1

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
    echo -e "  - Redis:         ${BLUE}localhost:6381${NC}"
    echo -e "  - Ollama:        ${BLUE}localhost:11434${NC}"
    echo -e "  - PostgreSQL:    ${BLUE}Neon (Cloud)${NC}"
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
    # Parse command line arguments first
    parse_arguments "$@"

    print_header

    # Show mode information
    if [ "$AUTO_MODE" = true ]; then
        echo -e "${GREEN}Running in AUTOMATIC mode${NC}"
        echo -e "Installation directory: ${BLUE}$INSTALL_DIR${NC}"
        echo ""
    fi

    check_root
    detect_package_manager
    get_project_root

    echo ""
    echo "This script will install and configure:"
    echo "  - Node.js 20.x"
    echo "  - Docker and Docker Compose"
    echo "  - Redis (via Docker)"
    echo "  - Ollama (via Docker)"
    echo "  - Project dependencies"
    echo ""
    echo -e "Installation directory: ${BLUE}$INSTALL_DIR${NC}"
    echo ""

    # Use fallback confirmation (auto-confirms in AUTO_MODE)
    if ! confirm_with_fallback "Continue with installation?" "y"; then
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
