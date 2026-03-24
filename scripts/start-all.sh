#!/bin/bash
# =============================================================================
#  Start all VCS AI Agent services + Nginx
# =============================================================================
#  Usage: bash start-all.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SERVICES=(
    "rag-agent"
    "sql-agent"
    "construction-agent"
    "ingestion-api"
    "gateway-service"
)

echo "=========================================="
echo "  Starting VCS AI Agents"
echo "=========================================="

# Start Nginx first (the gateway)
echo -e "${YELLOW}Starting Nginx (port 8000)...${NC}"
sudo systemctl start nginx
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}  Nginx: RUNNING${NC}"
else
    echo -e "${RED}  Nginx: FAILED${NC}"
fi

# Start all agent services
for svc in "${SERVICES[@]}"; do
    echo -e "${YELLOW}Starting ${svc}...${NC}"
    sudo systemctl start "$svc" 2>/dev/null || true

    sleep 1

    if systemctl is-active --quiet "$svc"; then
        echo -e "${GREEN}  ${svc}: RUNNING${NC}"
    else
        echo -e "${RED}  ${svc}: FAILED (check: journalctl -u ${svc} -n 20)${NC}"
    fi
done

echo ""
echo "=========================================="
echo -e "${GREEN}  All services started${NC}"
echo "=========================================="
echo ""
echo "  Test with:"
echo "    curl http://localhost:8000/gateway/health"
echo "    curl http://localhost:8000/rag/health"
echo "    curl http://localhost:8000/sql/health"
echo "    curl http://localhost:8000/construction/health"
echo ""
