#!/bin/bash

# ===========================================
# Grammarly Clone - Service Status Script
# ===========================================
#
# Shows the status of all project services
#
# Usage:
#   ./status.sh              # Show basic status
#   ./status.sh --detailed   # Show detailed status with logs
#   ./status.sh --json       # Output as JSON
# ===========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
DETAILED=false
JSON_OUTPUT=false

for arg in "$@"; do
    case $arg in
        --detailed|-d)
            DETAILED=true
            ;;
        --json|-j)
            JSON_OUTPUT=true
            ;;
        --help|-h)
            echo "Usage: ./status.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --detailed, -d   Show detailed status with health info"
            echo "  --json, -j       Output status as JSON"
            echo "  --help, -h       Show this help"
            exit 0
            ;;
    esac
done

# Get project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default ports (read from override if exists)
POSTGRES_PORT=5434
REDIS_PORT=6381
API_PORT=3002
WEB_PORT=5173

# Check if override file exists and read ports
if [ -f "$PROJECT_ROOT/docker-compose.override.yml" ]; then
    OVERRIDE_POSTGRES=$(grep -A2 'postgres:' "$PROJECT_ROOT/docker-compose.override.yml" | grep -oP '\d+(?=:5432)')
    OVERRIDE_REDIS=$(grep -A2 'redis:' "$PROJECT_ROOT/docker-compose.override.yml" | grep -oP '\d+(?=:6379)')
    [ -n "$OVERRIDE_POSTGRES" ] && POSTGRES_PORT=$OVERRIDE_POSTGRES
    [ -n "$OVERRIDE_REDIS" ] && REDIS_PORT=$OVERRIDE_REDIS
fi

# Status functions
check_docker_running() {
    docker info &> /dev/null
    return $?
}

check_container_status() {
    local container=$1
    local status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
    echo "$status"
}

check_container_health() {
    local container=$1
    local health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null)
    echo "$health"
}

get_container_uptime() {
    local container=$1
    local started=$(docker inspect -f '{{.State.StartedAt}}' "$container" 2>/dev/null)
    if [ -n "$started" ] && [ "$started" != "0001-01-01T00:00:00Z" ]; then
        # Calculate uptime
        local start_ts=$(date -d "$started" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${started%%.*}" +%s 2>/dev/null)
        local now_ts=$(date +%s)
        local diff=$((now_ts - start_ts))
        
        if [ $diff -lt 60 ]; then
            echo "${diff}s"
        elif [ $diff -lt 3600 ]; then
            echo "$((diff / 60))m"
        elif [ $diff -lt 86400 ]; then
            echo "$((diff / 3600))h $((diff % 3600 / 60))m"
        else
            echo "$((diff / 86400))d $((diff % 86400 / 3600))h"
        fi
    else
        echo "N/A"
    fi
}

check_port_listening() {
    local port=$1
    if command -v ss &> /dev/null; then
        ss -tuln 2>/dev/null | grep -q ":$port "
    elif command -v netstat &> /dev/null; then
        netstat -tuln 2>/dev/null | grep -q ":$port "
    else
        return 1
    fi
}

get_postgres_connections() {
    docker exec grammarly_postgres psql -U postgres -d grammarly_clone -t -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'grammarly_clone';" 2>/dev/null | tr -d ' '
}

get_redis_info() {
    docker exec grammarly_redis redis-cli info clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r'
}

# Print functions
print_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}"
        echo "==========================================="
        echo "     Grammarly Clone - Service Status"
        echo "==========================================="
        echo -e "${NC}"
        echo ""
    fi
}

print_service_status() {
    local name=$1
    local status=$2
    local port=$3
    local extra=$4
    
    if [ "$JSON_OUTPUT" = true ]; then
        return
    fi
    
    local status_icon=""
    local status_color=""
    
    case $status in
        "running")
            status_icon="●"
            status_color="${GREEN}"
            ;;
        "healthy")
            status_icon="●"
            status_color="${GREEN}"
            ;;
        "unhealthy")
            status_icon="●"
            status_color="${RED}"
            ;;
        "starting")
            status_icon="◐"
            status_color="${YELLOW}"
            ;;
        "stopped"|"exited")
            status_icon="○"
            status_color="${RED}"
            ;;
        *)
            status_icon="?"
            status_color="${YELLOW}"
            ;;
    esac
    
    printf "  ${status_color}${status_icon}${NC} %-20s" "$name"
    printf "%-12s" "$status"
    [ -n "$port" ] && printf "Port: %-8s" "$port"
    [ -n "$extra" ] && printf "%s" "$extra"
    echo ""
}

# Main status check
main() {
    print_header
    
    # Check Docker
    if ! check_docker_running; then
        if [ "$JSON_OUTPUT" = true ]; then
            echo '{"status":"error","message":"Docker is not running"}'
        else
            echo -e "  ${RED}✗${NC} Docker is not running"
        fi
        exit 1
    fi
    
    # Initialize JSON output
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{"
        echo '  "timestamp": "'$(date -Iseconds)'",'
        echo '  "services": {'
    fi
    
    # PostgreSQL status
    pg_status=$(check_container_status "grammarly_postgres")
    pg_health=$(check_container_health "grammarly_postgres")
    pg_uptime=$(get_container_uptime "grammarly_postgres")
    pg_conns=""
    
    if [ "$pg_status" = "running" ]; then
        pg_conns=$(get_postgres_connections)
        [ -n "$pg_conns" ] && pg_extra="Connections: $pg_conns"
    fi
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '    "postgresql": {'
        echo "      \"status\": \"$pg_status\","
        echo "      \"health\": \"$pg_health\","
        echo "      \"port\": $POSTGRES_PORT,"
        echo "      \"uptime\": \"$pg_uptime\","
        echo "      \"connections\": \"$pg_conns\""
        echo '    },'
    else
        print_service_status "PostgreSQL" "${pg_health:-$pg_status}" "$POSTGRES_PORT" "$pg_extra (uptime: $pg_uptime)"
    fi
    
    # Redis status
    redis_status=$(check_container_status "grammarly_redis")
    redis_health=$(check_container_health "grammarly_redis")
    redis_uptime=$(get_container_uptime "grammarly_redis")
    redis_clients=""
    
    if [ "$redis_status" = "running" ]; then
        redis_clients=$(get_redis_info)
    fi
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '    "redis": {'
        echo "      \"status\": \"$redis_status\","
        echo "      \"health\": \"$redis_health\","
        echo "      \"port\": $REDIS_PORT,"
        echo "      \"uptime\": \"$redis_uptime\","
        echo "      \"clients\": \"$redis_clients\""
        echo '    },'
    else
        [ -n "$redis_clients" ] && redis_extra="Clients: $redis_clients"
        print_service_status "Redis" "${redis_health:-$redis_status}" "$REDIS_PORT" "$redis_extra (uptime: $redis_uptime)"
    fi
    
    # API status (check if port is listening)
    api_listening=$(check_port_listening $API_PORT && echo "running" || echo "stopped")
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '    "api": {'
        echo "      \"status\": \"$api_listening\","
        echo "      \"port\": $API_PORT"
        echo '    },'
    else
        print_service_status "API Server" "$api_listening" "$API_PORT" ""
    fi
    
    # Web status (check if port is listening)
    web_listening=$(check_port_listening $WEB_PORT && echo "running" || echo "stopped")
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '    "web": {'
        echo "      \"status\": \"$web_listening\","
        echo "      \"port\": $WEB_PORT"
        echo '    }'
    else
        print_service_status "Web Frontend" "$web_listening" "$WEB_PORT" ""
    fi
    
    # Close JSON
    if [ "$JSON_OUTPUT" = true ]; then
        echo '  }'
        echo "}"
    fi
    
    # Detailed output
    if [ "$DETAILED" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${CYAN}Docker Containers:${NC}"
        docker ps --filter "name=grammarly" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null
        
        echo ""
        echo -e "${CYAN}Resource Usage:${NC}"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker ps -q --filter "name=grammarly") 2>/dev/null
        
        echo ""
        echo -e "${CYAN}Recent Logs (last 5 lines each):${NC}"
        echo ""
        echo -e "${YELLOW}PostgreSQL:${NC}"
        docker logs --tail 5 grammarly_postgres 2>&1 | sed 's/^/  /'
        echo ""
        echo -e "${YELLOW}Redis:${NC}"
        docker logs --tail 5 grammarly_redis 2>&1 | sed 's/^/  /'
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${CYAN}Quick Links:${NC}"
        echo -e "  Web:  ${BLUE}http://localhost:$WEB_PORT${NC}"
        echo -e "  API:  ${BLUE}http://localhost:$API_PORT${NC}"
        echo ""
        echo -e "${CYAN}Nginx Proxy Config:${NC}"
        echo -e "  Frontend -> ${BLUE}http://127.0.0.1:$WEB_PORT${NC}"
        echo -e "  Backend  -> ${BLUE}http://127.0.0.1:$API_PORT${NC}"
        echo ""
    fi
}

main "$@"
