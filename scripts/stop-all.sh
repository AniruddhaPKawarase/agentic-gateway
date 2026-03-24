#!/bin/bash
# =============================================================================
#  Stop all VCS AI Agent services
# =============================================================================
#  Usage: bash stop-all.sh
#
#  Note: This stops all agent services but keeps Nginx running.
#  To stop Nginx too, pass --nginx flag: bash stop-all.sh --nginx
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SERVICES=(
    "gateway-service"
    "ingestion-api"
    "construction-agent"
    "sql-agent"
    "rag-agent"
)

echo "=========================================="
echo "  Stopping VCS AI Agents"
echo "=========================================="

for svc in "${SERVICES[@]}"; do
    echo -e "${YELLOW}Stopping ${svc}...${NC}"
    sudo systemctl stop "$svc" 2>/dev/null || true
    echo -e "${GREEN}  ${svc}: STOPPED${NC}"
done

# Optionally stop Nginx
if [[ "${1:-}" == "--nginx" ]]; then
    echo -e "${YELLOW}Stopping Nginx...${NC}"
    sudo systemctl stop nginx
    echo -e "${GREEN}  Nginx: STOPPED${NC}"
fi

echo ""
echo -e "${GREEN}  All agent services stopped${NC}"
echo ""
