#!/bin/bash

# ===========================================
# DANGER: Uninstall / Cleanup Script
# ===========================================
# This script will:
# 1. Stop and remove all containers
# 2. DELETE ALL LOCAL DATA VOLUMES (Redis, Ollama)
# 3. Remove project Docker images
# 4. Delete node_modules and build artifacts
# 5. Optionally delete the entire project directory
# NOTE: Remote database (Neon) is NOT affected
# ===========================================

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}"
echo "==========================================="
echo "   ⚠️   DANGER ZONE: PROJECT UNINSTALL   ⚠️"
echo "==========================================="
echo -e "${NC}"
echo "This script will completely wipe the project environment."
echo "The following will be DELETED PERMANENTLY:"
echo "  - All Docker containers (API, Redis, Ollama, Web)"
echo "  - All local data volumes (Redis, Ollama)"
echo "  - All Docker images created by this project"
echo "  - All node_modules and build files"
echo ""
echo "NOTE: Remote database (Neon) is NOT affected."
echo ""

# First Confirmation
read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirm1
if [ "$confirm1" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Second Confirmation
echo ""
echo -e "${RED}WARNING: This is your last chance. Data will be lost.${NC}"
read -p "Are you REALLY sure? (type 'delete-everything' to confirm): " confirm2
if [ "$confirm2" != "delete-everything" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${CYAN}[*] Starting cleanup...${NC}"

# Detect docker compose
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

# 1. Docker Cleanup
echo -e "${YELLOW}[1/4] Removing Docker resources...${NC}"
$COMPOSE_CMD down -v --rmi all --remove-orphans

# Remove old volumes that might have been created with generic names
echo -e "${YELLOW}      Removing any leftover volumes...${NC}"
docker volume rm redis_data ollama_data 2>/dev/null || true
docker volume rm grammarly_redis_data grammarly_ollama_data 2>/dev/null || true
docker volume rm grammarly_remotedb_redis_data grammarly_remotedb_ollama_data 2>/dev/null || true
echo -e "${CYAN}Docker resources removed.${NC}"

# 2. Node Modules Cleanup
echo -e "${YELLOW}[2/4] Removing node_modules...${NC}"
find . -name "node_modules" -type d -prune -exec rm -rf '{}' +
echo -e "${CYAN}node_modules removed.${NC}"

# 3. Artifacts Cleanup
echo -e "${YELLOW}[3/4] Removing build artifacts (.turbo, dist, .next)...${NC}"
rm -rf .turbo dist build .next coverage
echo -e "${CYAN}Artifacts removed.${NC}"

# 4. File Deletion (Optional/Manual advice)
echo -e "${YELLOW}[4/4] Final Step${NC}"
echo ""
echo -e "${GREEN}The project environment has been wiped.${NC}"
echo "To completely remove the project files, run this command after exiting:"
echo ""
echo -e "    ${RED}cd .. && rm -rf $(basename "$PWD")${NC}"
echo ""
