#!/bin/bash
# =============================================================================
#  Restart a single VCS AI Agent service
# =============================================================================
#  Usage: bash restart-agent.sh <agent-name>
#
#  Agent names:
#    rag           — RAG Agent (port 8001)
#    sql           — SQL Intelligence Agent (port 8002)
#    construction  — Construction Intelligence Agent (port 8003)
#    ingestion     — Ingestion API (port 8004)
#    gateway       — Gateway Health Service (port 8005)
#    nginx         — Nginx reverse proxy (port 8000)
#    all           — All services
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Map friendly names to service names
declare -A SERVICE_MAP=(
    ["rag"]="rag-agent"
    ["sql"]="sql-agent"
    ["construction"]="construction-agent"
    ["ingestion"]="ingestion-api"
    ["gateway"]="gateway-service"
    ["nginx"]="nginx"
)

if [ $# -eq 0 ]; then
    echo "Usage: bash restart-agent.sh <agent-name>"
    echo ""
    echo "Available agents:"
    echo "  rag           — RAG Agent (port 8001)"
    echo "  sql           — SQL Intelligence Agent (port 8002)"
    echo "  construction  — Construction Intelligence Agent (port 8003)"
    echo "  ingestion     — Ingestion API (port 8004)"
    echo "  gateway       — Gateway Health Service (port 8005)"
    echo "  nginx         — Nginx reverse proxy (port 8000)"
    echo "  all           — All services"
    exit 1
fi

AGENT="$1"

if [ "$AGENT" == "all" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "$SCRIPT_DIR/stop-all.sh"
    sleep 2
    bash "$SCRIPT_DIR/start-all.sh"
    exit 0
fi

if [ -z "${SERVICE_MAP[$AGENT]+x}" ]; then
    echo -e "${RED}Unknown agent: $AGENT${NC}"
    echo "Available: rag, sql, construction, ingestion, gateway, nginx, all"
    exit 1
fi

SVC="${SERVICE_MAP[$AGENT]}"

echo -e "${YELLOW}Restarting ${SVC}...${NC}"
sudo systemctl restart "$SVC"

sleep 2

if systemctl is-active --quiet "$SVC"; then
    echo -e "${GREEN}  ${SVC}: RUNNING${NC}"
else
    echo -e "${RED}  ${SVC}: FAILED${NC}"
    echo "  Check logs: journalctl -u ${SVC} -n 30"
fi
