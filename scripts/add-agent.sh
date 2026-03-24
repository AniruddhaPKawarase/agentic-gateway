#!/bin/bash
# =============================================================================
#  Add a new agent to the VCS Gateway
# =============================================================================
#  Usage: bash add-agent.sh <name> <port> <working-dir> <start-command>
#
#  Example:
#    bash add-agent.sh safety 8006 /home/ubuntu/PROD_SETUP/safety-agent "python main.py"
#
#  What it does:
#    1. Generates a systemd service file
#    2. Adds Nginx location block (prints instructions)
#    3. Prints next steps
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -lt 4 ]; then
    echo "Usage: bash add-agent.sh <name> <port> <working-dir> <start-command>"
    echo ""
    echo "Arguments:"
    echo "  name          — Short name (e.g., 'safety', 'quality')"
    echo "  port          — Internal port (e.g., 8006)"
    echo "  working-dir   — Full path to agent folder"
    echo "  start-command — How to start the agent (e.g., 'python main.py')"
    echo ""
    echo "Example:"
    echo "  bash add-agent.sh safety 8006 /home/ubuntu/PROD_SETUP/safety-agent 'python main.py'"
    exit 1
fi

NAME="$1"
PORT="$2"
WORKDIR="$3"
CMD="$4"
SERVICE_NAME="${NAME}-agent"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  Adding New Agent: $NAME"
echo "=========================================="
echo ""
echo "  Name:         $NAME"
echo "  Port:         $PORT"
echo "  Working Dir:  $WORKDIR"
echo "  Command:      $CMD"
echo "  Service Name: $SERVICE_NAME"
echo ""

# ── Generate systemd service file ────────────────────────────────────────────
SERVICE_FILE="$GATEWAY_DIR/services/${SERVICE_NAME}.service"

cat > "$SERVICE_FILE" << HEREDOC
# Auto-generated service file for ${NAME} agent
[Unit]
Description=VCS ${NAME^} Agent (Port ${PORT})
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=${WORKDIR}
EnvironmentFile=${WORKDIR}/.env
ExecStart=${WORKDIR}/venv/bin/${CMD}
Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
LimitNOFILE=65536
TimeoutStartSec=30
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
HEREDOC

echo -e "${GREEN}  Created: $SERVICE_FILE${NC}"

# ── Print Nginx config to add ────────────────────────────────────────────────
NGINX_BLOCK="
    # ======================================================================
    #  ${NAME^} Agent — Port ${PORT} — Prefix /${NAME}/
    # ======================================================================

    upstream ${NAME}_agent {
        server 127.0.0.1:${PORT};
        keepalive 8;
    }

    location /${NAME}/ {
        proxy_pass http://${NAME}_agent/;
        proxy_http_version 1.1;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_set_header Connection '';
    }
"

echo ""
echo -e "${YELLOW}  Add this to Nginx config ($GATEWAY_DIR/nginx/vcs-agents.conf):${NC}"
echo "  ─────────────────────────────────────────────"
echo "$NGINX_BLOCK"
echo "  ─────────────────────────────────────────────"

# ── Print next steps ─────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}  Next steps:${NC}"
echo ""
echo "  1. Add the Nginx block above to: $GATEWAY_DIR/nginx/vcs-agents.conf"
echo "     (Add the 'upstream' block near the top with other upstreams)"
echo "     (Add the 'location' block inside the 'server' block)"
echo ""
echo "  2. Install and start the service:"
echo "     sudo cp $SERVICE_FILE /etc/systemd/system/"
echo "     sudo systemctl daemon-reload"
echo "     sudo systemctl enable $SERVICE_NAME"
echo "     sudo systemctl start $SERVICE_NAME"
echo ""
echo "  3. Reload Nginx:"
echo "     sudo cp $GATEWAY_DIR/nginx/vcs-agents.conf /etc/nginx/sites-available/vcs-agents"
echo "     sudo nginx -t && sudo systemctl reload nginx"
echo ""
echo "  4. Test:"
echo "     curl http://localhost:${PORT}/health    (direct)"
echo "     curl http://localhost:8000/${NAME}/health (through gateway)"
echo ""
echo "  5. Update gateway health service:"
echo "     Add '${NAME}' to AGENTS dict in $GATEWAY_DIR/health_service/main.py"
echo "     sudo systemctl restart gateway-service"
echo ""
echo -e "${GREEN}  Done! Agent '${NAME}' is ready for deployment.${NC}"
