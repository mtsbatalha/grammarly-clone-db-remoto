#!/bin/bash

# ===========================================
# Grammarly Clone - Stop Script (Linux/Mac)
# ===========================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

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
$DOCKER_COMPOSE -f docker-compose.dev.yml down

echo ""
echo -e "${GREEN}[OK]${NC} All services stopped"
echo ""
