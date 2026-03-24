#!/bin/bash
# =============================================================================
#  VCS AI Agents — Full Deployment Script
# =============================================================================
#  Run this for first-time deployment or re-deployment:
#    sudo bash deploy.sh
#
#  What it does:
#    1. Runs install.sh (Nginx, systemd, venvs)
#    2. Starts all services
#    3. Verifies everything is working
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  VCS AI Agents — Full Deployment"
echo "=========================================="
echo ""

# ── Step 1: Install ──────────────────────────────────────────────────────────
echo -e "${YELLOW}Step 1: Running installation...${NC}"
sudo bash "$SCRIPT_DIR/install.sh"

# ── Step 2: Start all ────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 2: Starting all services...${NC}"
bash "$SCRIPT_DIR/start-all.sh"

# ── Step 3: Wait and verify ──────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Step 3: Verifying (waiting 5 seconds for services to initialize)...${NC}"
sleep 5

bash "$SCRIPT_DIR/status.sh"

echo ""
echo "=========================================="
echo -e "${GREEN}  Deployment Complete!${NC}"
echo "=========================================="
echo ""
echo "  Your agents are accessible at:"
echo "    RAG Agent:          http://your-vm:8000/rag/"
echo "    SQL Agent:          http://your-vm:8000/sql/"
echo "    Construction Agent: http://your-vm:8000/construction/"
echo "    Ingestion API:      http://your-vm:8000/ingestion/"
echo "    Gateway Health:     http://your-vm:8000/gateway/health"
echo ""
echo "  Management commands:"
echo "    bash $SCRIPT_DIR/status.sh              — Check all statuses"
echo "    bash $SCRIPT_DIR/restart-agent.sh rag   — Restart single agent"
echo "    bash $SCRIPT_DIR/logs.sh sql             — View agent logs"
echo "    bash $SCRIPT_DIR/stop-all.sh             — Stop everything"
echo ""
