#!/bin/bash
# =============================================================================
#  VCS AI Agents — SSL Certificate Renewal Script
# =============================================================================
#  Manual renewal for Let's Encrypt certificate.
#    sudo bash renew-ssl.sh
#    sudo bash renew-ssl.sh --dry-run    # Test without actually renewing
#
#  Auto-renewal is handled by systemd timer or cron (set up by
#  setup-ssl-letsencrypt.sh). Use this script only for manual renewal
#  or troubleshooting.
# =============================================================================

set -euo pipefail

DOMAIN="ai.ifieldsmart.com"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Check root ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run as root (sudo bash renew-ssl.sh)${NC}"
    exit 1
fi

# ── Check for dry-run flag ───────────────────────────────────────────────────
DRY_RUN=""
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN="--dry-run"
    echo -e "${CYAN}  Running in DRY-RUN mode (no actual renewal)${NC}"
    echo ""
fi

# ── Show current certificate info ────────────────────────────────────────────
echo "=========================================="
echo "  VCS AI Agents — SSL Certificate Renewal"
echo "=========================================="
echo ""

echo -e "${YELLOW}Current certificate status:${NC}"
if command -v certbot &> /dev/null; then
    certbot certificates 2>/dev/null || echo "  No certbot certificates found"
elif [ -f "/etc/ssl/certs/vcs-agents.crt" ]; then
    echo "  Self-signed certificate:"
    openssl x509 -in /etc/ssl/certs/vcs-agents.crt -noout -subject -dates 2>/dev/null || echo "  Could not read certificate"
else
    echo -e "${RED}  No SSL certificate found!${NC}"
    exit 1
fi
echo ""

# ── Renew ────────────────────────────────────────────────────────────────────
if command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Renewing Let's Encrypt certificate...${NC}"
    echo ""

    # $DRY_RUN is intentionally unquoted: when empty, it must expand to nothing (not "")
    if certbot renew $DRY_RUN --deploy-hook "nginx -t && systemctl reload nginx" 2>&1; then
        echo ""
        echo -e "${GREEN}  Renewal successful!${NC}"
    else
        echo ""
        echo -e "${RED}  Renewal failed!${NC}"
        echo ""
        echo "  Troubleshooting:"
        echo "    - Check port 80 is open (needed for ACME challenge)"
        echo "    - Verify DNS: dig $DOMAIN A"
        echo "    - Check certbot logs: journalctl -u certbot"
        echo "    - Manual debug: certbot renew --dry-run -v"
        exit 1
    fi
else
    echo -e "${YELLOW}Certbot not installed. Self-signed certificate detected.${NC}"
    echo ""

    if [ -n "$DRY_RUN" ]; then
        echo "  Dry-run: Would regenerate self-signed cert for $DOMAIN"
    else
        echo "  Regenerating self-signed certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/vcs-agents.key \
            -out /etc/ssl/certs/vcs-agents.crt \
            -subj "/C=US/ST=State/L=City/O=VCS/OU=AI-Agents/CN=$DOMAIN"

        chmod 600 /etc/ssl/private/vcs-agents.key
        chmod 644 /etc/ssl/certs/vcs-agents.crt

        nginx -t && systemctl reload nginx
        echo -e "${GREEN}  Self-signed certificate regenerated (365 days)${NC}"
    fi
fi

# ── Verify ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Verification:${NC}"

# Check if Nginx is running
if systemctl is-active --quiet nginx; then
    echo -e "  Nginx: ${GREEN}running${NC}"
else
    echo -e "  Nginx: ${RED}stopped${NC}"
fi

# Check HTTPS connectivity
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "https://$DOMAIN/gateway/health" --connect-timeout 5 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "  HTTPS (https://$DOMAIN/gateway/health): ${GREEN}200 OK${NC}"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "  HTTPS: ${YELLOW}could not connect (may be expected in dry-run)${NC}"
    else
        echo -e "  HTTPS: ${RED}HTTP $HTTP_CODE${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Done.${NC}"
