#!/bin/bash

# ===========================================
# Grammarly Clone - Stop Script (Linux/Mac)
# ===========================================
#
# Usage:
#   ./stop.sh              # Stop all services
#   ./stop.sh --clean      # Stop and remove port override file
# ===========================================

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
CLEAN_OVERRIDE=false
for arg in "$@"; do
    case $arg in
        --clean|-c)
            CLEAN_OVERRIDE=true
            ;;
    esac
done

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "==========================================="
echo "     Grammarly Clone - Stopping..."
echo "==========================================="
echo -e "${NC}"

cd "$PROJECT_ROOT"

# Use docker compose (new) or docker-compose (legacy)
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo -e "${GREEN}[*]${NC} Stopping Docker services..."

# Stop with override if it exists
if [ -f "docker-compose.override.yml" ]; then
    $DOCKER_COMPOSE -f docker-compose.dev.yml -f docker-compose.override.yml down
else
    $DOCKER_COMPOSE -f docker-compose.dev.yml down
fi

# Clean override file if requested
if [ "$CLEAN_OVERRIDE" = true ] && [ -f "docker-compose.override.yml" ]; then
    echo -e "${GREEN}[*]${NC} Removing port override file..."
    rm -f "docker-compose.override.yml"
    echo -e "${GREEN}[OK]${NC} Override file removed"
    echo -e "${YELLOW}[NOTE]${NC} Default ports will be used on next start"
fi

echo ""
echo -e "${GREEN}[OK]${NC} All services stopped"
echo ""
