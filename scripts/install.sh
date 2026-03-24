#!/bin/bash
# =============================================================================
#  VCS AI Agents — One-Time Installation Script
# =============================================================================
#  Run this ONCE on a fresh VM to set up everything:
#    sudo bash install.sh
#
#  What it does:
#    1. Installs Nginx (if not already installed)
#    2. Copies Nginx config and enables it
#    3. Copies systemd service files and enables them
#    4. Creates Python venvs for new services (ingestion API, gateway)
#    5. Tests Nginx config
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
#  UPDATE THIS to match your VM deployment path
PROD_SETUP_DIR="/home/ubuntu/PROD_SETUP"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  VCS AI Agents — Installation"
echo "=========================================="
echo ""
echo "  PROD_SETUP path: $PROD_SETUP_DIR"
echo ""

# ── Check root ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run as root (sudo bash install.sh)${NC}"
    exit 1
fi

# ── Install Nginx ────────────────────────────────────────────────────────────
echo -e "${YELLOW}[1/5] Installing Nginx...${NC}"
if command -v nginx &> /dev/null; then
    echo -e "${GREEN}  Nginx already installed: $(nginx -v 2>&1)${NC}"
else
    apt-get update -qq
    apt-get install -y nginx
    echo -e "${GREEN}  Nginx installed successfully${NC}"
fi

# ── Configure Nginx ──────────────────────────────────────────────────────────
echo -e "${YELLOW}[2/5] Configuring Nginx...${NC}"

cp "$GATEWAY_DIR/nginx/vcs-agents.conf" /etc/nginx/sites-available/vcs-agents
ln -sf /etc/nginx/sites-available/vcs-agents /etc/nginx/sites-enabled/vcs-agents

# Remove default site if it exists (it conflicts with port 80, but we use 8000)
# rm -f /etc/nginx/sites-enabled/default

# Test config
if nginx -t 2>&1; then
    echo -e "${GREEN}  Nginx config valid${NC}"
else
    echo -e "${RED}  Nginx config INVALID — check $GATEWAY_DIR/nginx/vcs-agents.conf${NC}"
    exit 1
fi

# ── Install systemd services ────────────────────────────────────────────────
echo -e "${YELLOW}[3/5] Installing systemd services...${NC}"

SERVICES=(
    "rag-agent"
    "sql-agent"
    "construction-agent"
    "ingestion-api"
    "gateway-service"
)

for svc in "${SERVICES[@]}"; do
    cp "$GATEWAY_DIR/services/${svc}.service" "/etc/systemd/system/${svc}.service"
    echo "  Installed: ${svc}.service"
done

systemctl daemon-reload
echo -e "${GREEN}  All services installed${NC}"

# ── Enable services (auto-start on boot) ────────────────────────────────────
echo -e "${YELLOW}[4/5] Enabling services for auto-start...${NC}"

for svc in "${SERVICES[@]}"; do
    systemctl enable "$svc" 2>/dev/null || true
    echo "  Enabled: $svc"
done

systemctl enable nginx 2>/dev/null || true
echo -e "${GREEN}  All services enabled${NC}"

# ── Create venvs for new services (if missing) ──────────────────────────────
echo -e "${YELLOW}[5/5] Setting up Python environments...${NC}"

# Gateway health service venv
GATEWAY_HS_DIR="$PROD_SETUP_DIR/gateway/health_service"
if [ -d "$GATEWAY_HS_DIR" ] && [ ! -d "$GATEWAY_HS_DIR/venv" ]; then
    echo "  Creating venv for gateway health service..."
    python3 -m venv "$GATEWAY_HS_DIR/venv"
    "$GATEWAY_HS_DIR/venv/bin/pip" install --quiet fastapi uvicorn httpx python-dotenv
    echo -e "${GREEN}  Gateway health service venv created${NC}"
fi

# Ingestion API venv (uses parent's venv or its own)
INGEST_DIR="$PROD_SETUP_DIR/INGESTION_for_RAG_agent"
if [ -d "$INGEST_DIR" ] && [ ! -d "$INGEST_DIR/venv" ]; then
    echo "  Creating venv for ingestion API..."
    python3 -m venv "$INGEST_DIR/venv"
    "$INGEST_DIR/venv/bin/pip" install --quiet fastapi uvicorn python-dotenv
    # Install existing pipeline dependencies
    if [ -f "$INGEST_DIR/requirements.txt" ]; then
        "$INGEST_DIR/venv/bin/pip" install --quiet -r "$INGEST_DIR/requirements.txt"
    fi
    echo -e "${GREEN}  Ingestion API venv created${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}  Installation Complete!${NC}"
echo "=========================================="
echo ""
echo "  Next steps:"
echo "    1. Update .env files for each agent (set correct ports)"
echo "    2. Run: bash $SCRIPT_DIR/start-all.sh"
echo "    3. Verify: bash $SCRIPT_DIR/status.sh"
echo "    4. Test: curl http://localhost:8000/gateway/health"
echo ""
