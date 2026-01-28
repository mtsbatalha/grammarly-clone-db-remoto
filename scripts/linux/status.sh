#!/bin/bash

# ===========================================
# Grammarly Clone - Service Status Script
# ===========================================
#
# Shows the status of all project services
# Automatically detects local vs remote database mode
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
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Default ports
MYSQL_PORT=3307
REDIS_PORT=6381
API_PORT=3002
WEB_PORT=5173

# Database mode (will be detected)
DB_MODE="unknown"

# Detect if DATABASE_URL points to a remote or local database
detect_database_mode() {
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
    
    if [ -z "$DATABASE_URL" ]; then
        DB_MODE="local"
        return
    fi
    
    # Extract host from DATABASE_URL
    # Format: mysql://user:pass@host:port/database
    DB_HOST=$(echo "$DATABASE_URL" | sed -E 's|^mysql://[^@]+@([^:/]+).*|\1|')
    
    # Extract port from DATABASE_URL (default 3306)
    DB_PORT=$(echo "$DATABASE_URL" | sed -E 's|^mysql://[^@]+@[^:]+:([0-9]+)/.*|\1|')
    if [ -z "$DB_PORT" ] || [ "$DB_PORT" = "$DATABASE_URL" ]; then
        DB_PORT="3306"
    fi
    
    # Check if host is local
    if [ -z "$DB_HOST" ] || [ "$DB_HOST" = "localhost" ] || [ "$DB_HOST" = "127.0.0.1" ] || [ "$DB_HOST" = "0.0.0.0" ]; then
        DB_MODE="local"
    else
        DB_MODE="remote"
        DB_REMOTE_HOST="$DB_HOST"
        DB_REMOTE_PORT="$DB_PORT"
    fi
}

# Check remote database connection and latency
check_remote_db_status() {
    local host=$1
    local port=$2
    
    DB_CONN_STATUS="unknown"
    DB_LATENCY="N/A"
    
    # Check if we can reach the host (TCP connection test)
    if command -v nc &> /dev/null; then
        # Use netcat for connection test with timeout
        start_time=$(date +%s%3N 2>/dev/null || echo "0")
        if nc -z -w 3 "$host" "$port" 2>/dev/null; then
            end_time=$(date +%s%3N 2>/dev/null || echo "0")
            DB_CONN_STATUS="connected"
            if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
                DB_LATENCY="$((end_time - start_time))ms"
            fi
        else
            DB_CONN_STATUS="unreachable"
        fi
    elif command -v timeout &> /dev/null; then
        # Fallback: use bash /dev/tcp with timeout
        start_time=$(date +%s%3N 2>/dev/null || echo "0")
        if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
            end_time=$(date +%s%3N 2>/dev/null || echo "0")
            DB_CONN_STATUS="connected"
            if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
                DB_LATENCY="$((end_time - start_time))ms"
            fi
        else
            DB_CONN_STATUS="unreachable"
        fi
    else
        # Last resort: try ping for host reachability
        if ping -c 1 -W 2 "$host" &>/dev/null; then
            DB_CONN_STATUS="host_reachable"
            DB_LATENCY=$(ping -c 1 "$host" 2>/dev/null | grep -oP 'time=\K[0-9.]+' | head -1)
            [ -n "$DB_LATENCY" ] && DB_LATENCY="${DB_LATENCY}ms"
        else
            DB_CONN_STATUS="unreachable"
        fi
    fi
}

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
        "remote")
            status_icon="☁"
            status_color="${CYAN}"
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
    # Detect database mode first
    detect_database_mode
    
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
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo '{'
        echo '  "timestamp": "'$(date -Iseconds)'",'
        echo '  "database_mode": "'$DB_MODE'",'
        echo '  "services": {'
    fi
    
    # MySQL status
    if [ "$DB_MODE" = "local" ]; then
        # Check local MySQL container
        mysql_status=$(check_container_status "grammarly_mysql")
        mysql_health=$(check_container_health "grammarly_mysql")
        mysql_uptime=$(get_container_uptime "grammarly_mysql")
        
        if [ "$JSON_OUTPUT" = true ]; then
            echo '    "mysql": {'
            echo "      \"mode\": \"local\","
            echo "      \"status\": \"$mysql_status\","
            echo "      \"health\": \"$mysql_health\","
            echo "      \"port\": $MYSQL_PORT,"
            echo "      \"uptime\": \"$mysql_uptime\""
            echo '    },'
        else
            if [ "$mysql_status" = "running" ]; then
                print_service_status "MySQL (Local)" "${mysql_health:-$mysql_status}" "$MYSQL_PORT" "(uptime: $mysql_uptime)"
            else
                print_service_status "MySQL (Local)" "${mysql_status:-stopped}" "$MYSQL_PORT" ""
            fi
        fi
    else
        # Remote database - check connection and latency
        check_remote_db_status "$DB_REMOTE_HOST" "$DB_REMOTE_PORT"
        
        if [ "$JSON_OUTPUT" = true ]; then
            echo '    "mysql": {'
            echo "      \"mode\": \"remote\","
            echo "      \"host\": \"$DB_REMOTE_HOST\","
            echo "      \"port\": $DB_REMOTE_PORT,"
            echo "      \"connection_status\": \"$DB_CONN_STATUS\","
            echo "      \"latency\": \"$DB_LATENCY\""
            echo '    },'
        else
            # Determine connection status color and icon
            local conn_icon=""
            local conn_color=""
            case $DB_CONN_STATUS in
                "connected")
                    conn_icon="●"
                    conn_color="${GREEN}"
                    ;;
                "host_reachable")
                    conn_icon="◐"
                    conn_color="${YELLOW}"
                    ;;
                "unreachable")
                    conn_icon="○"
                    conn_color="${RED}"
                    ;;
                *)
                    conn_icon="?"
                    conn_color="${YELLOW}"
                    ;;
            esac
            
            echo ""
            echo -e "  ${CYAN}╔══════════════════════════════════════════╗${NC}"
            echo -e "  ${CYAN}║${NC}         ${CYAN}☁  Remote Database${NC}              ${CYAN}║${NC}"
            echo -e "  ${CYAN}╠══════════════════════════════════════════╣${NC}"
            printf "  ${CYAN}║${NC}  %-12s ${BLUE}%-27s${NC}${CYAN}║${NC}\n" "Host:" "$DB_REMOTE_HOST"
            printf "  ${CYAN}║${NC}  %-12s ${BLUE}%-27s${NC}${CYAN}║${NC}\n" "Port:" "$DB_REMOTE_PORT"
            printf "  ${CYAN}║${NC}  %-12s ${conn_color}${conn_icon} %-25s${NC}${CYAN}║${NC}\n" "Connection:" "$DB_CONN_STATUS"
            printf "  ${CYAN}║${NC}  %-12s ${YELLOW}%-27s${NC}${CYAN}║${NC}\n" "Latency:" "$DB_LATENCY"
            echo -e "  ${CYAN}╚══════════════════════════════════════════╝${NC}"
            echo ""
        fi
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
        redis_extra=""
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
        
        if [ "$DB_MODE" = "local" ]; then
            echo -e "${YELLOW}MySQL:${NC}"
            docker logs --tail 5 grammarly_mysql 2>&1 | sed 's/^/  /'
            echo ""
        fi
        
        echo -e "${YELLOW}Redis:${NC}"
        docker logs --tail 5 grammarly_redis 2>&1 | sed 's/^/  /'
    fi
    
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${CYAN}Database Mode:${NC} ${YELLOW}$DB_MODE${NC}"
        echo ""
        echo -e "${CYAN}Quick Links:${NC}"
        echo -e "  Web:  ${BLUE}http://localhost:$WEB_PORT${NC}"
        echo -e "  API:  ${BLUE}http://localhost:$API_PORT${NC}"
        echo ""
    fi
}

main "$@"
