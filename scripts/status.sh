#!/bin/bash
# =============================================================================
#  Show status of all VCS AI Agent services
# =============================================================================
#  Usage: bash status.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "  VCS AI Agents — Status"
echo "=========================================="
echo ""

# Service status function
check_service() {
    local name="$1"
    local svc="$2"
    local port="$3"
    local prefix="$4"

    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        status="${GREEN}RUNNING${NC}"
    else
        status="${RED}STOPPED${NC}"
    fi

    printf "  %-25s %-15b Port: %-6s Prefix: %s\n" "$name" "$status" "$port" "$prefix"
}

# Check Nginx
echo -e "${BLUE}Gateway (Nginx):${NC}"
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "  Nginx Reverse Proxy      ${GREEN}RUNNING${NC}  Port: 8000   (public)"
else
    echo -e "  Nginx Reverse Proxy      ${RED}STOPPED${NC}  Port: 8000   (public)"
fi

echo ""
echo -e "${BLUE}Agent Services:${NC}"
check_service "RAG Agent" "rag-agent" "8001" "/rag/"
check_service "SQL Agent" "sql-agent" "8002" "/sql/"
check_service "Construction Agent" "construction-agent" "8003" "/construction/"
check_service "Ingestion API" "ingestion-api" "8004" "/ingestion/"
check_service "Gateway Health" "gateway-service" "8005" "/gateway/"

echo ""

# Quick health check via HTTP (if curl available)
if command -v curl &> /dev/null; then
    echo -e "${BLUE}HTTP Health Checks:${NC}"

    check_http() {
        local name="$1"
        local url="$2"
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || echo "000")
        if [ "$response" == "200" ]; then
            printf "  %-25s ${GREEN}OK (200)${NC}\n" "$name"
        elif [ "$response" == "000" ]; then
            printf "  %-25s ${RED}UNREACHABLE${NC}\n" "$name"
        else
            printf "  %-25s ${YELLOW}HTTP $response${NC}\n" "$name"
        fi
    }

    check_http "Gateway Health" "http://localhost:8000/gateway/health"
    check_http "RAG Agent" "http://localhost:8000/rag/health"
    check_http "SQL Agent" "http://localhost:8000/sql/health"
    check_http "Construction Agent" "http://localhost:8000/construction/health"
    check_http "Ingestion API" "http://localhost:8000/ingestion/health"
fi

echo ""
echo "=========================================="
echo ""
