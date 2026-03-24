#!/bin/bash
# =============================================================================
#  VCS AI Agents — Self-Signed SSL Setup Script
# =============================================================================
#  Run this to set up HTTPS with a self-signed certificate (for TESTING).
#    sudo bash setup-ssl-selfsigned.sh
#
#  What it does:
#    1. Installs OpenSSL (if not present)
#    2. Generates self-signed certificate (365-day validity)
#    3. Backs up current Nginx config
#    4. Deploys SSL-enabled Nginx config
#    5. Tests and reloads Nginx
#
#  After running:
#    - HTTPS available at: https://ai.ifieldsmart.com (port 443)
#    - HTTP redirect at: http://ai.ifieldsmart.com (port 80 → 443)
#    - HTTP fallback at: http://<ip>:8000 (unchanged)
#
#  NOTE: Self-signed certs trigger browser warnings.
#        Use curl -k for testing. Switch to Let's Encrypt for production.
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
DOMAIN="ai.ifieldsmart.com"
SSL_KEY="/etc/ssl/private/vcs-agents.key"
SSL_CERT="/etc/ssl/certs/vcs-agents.crt"
CERT_DAYS=365

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_SRC="$GATEWAY_DIR/nginx/vcs-agents-ssl.conf"
NGINX_CONF_DST="/etc/nginx/sites-available/vcs-agents"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/vcs-agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "  VCS AI Agents — Self-Signed SSL Setup"
echo "=========================================="
echo ""
echo "  Domain: $DOMAIN"
echo "  Certificate: $SSL_CERT"
echo "  Key: $SSL_KEY"
echo "  Validity: $CERT_DAYS days"
echo ""

# ── Check root ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run as root (sudo bash setup-ssl-selfsigned.sh)${NC}"
    exit 1
fi

# ── Step 1: Install OpenSSL ─────────────────────────────────────────────────
echo -e "${YELLOW}[1/5] Checking OpenSSL...${NC}"
if command -v openssl &> /dev/null; then
    echo -e "${GREEN}  OpenSSL already installed: $(openssl version)${NC}"
else
    echo "  Installing OpenSSL..."
    apt-get update -qq
    apt-get install -y openssl
    echo -e "${GREEN}  OpenSSL installed successfully${NC}"
fi

# ── Step 2: Generate Self-Signed Certificate ────────────────────────────────
echo -e "${YELLOW}[2/5] Generating self-signed certificate...${NC}"

if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
    echo -e "${CYAN}  Existing certificate found. Backing up...${NC}"
    cp "$SSL_CERT" "${SSL_CERT}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SSL_KEY" "${SSL_KEY}.bak.$(date +%Y%m%d%H%M%S)"
fi

# Create directories if they don't exist
mkdir -p /etc/ssl/private /etc/ssl/certs

# -addext adds Subject Alternative Name (SAN) — required by modern browsers (Chrome 58+)
# Without SAN, browsers reject with ERR_CERT_COMMON_NAME_INVALID (not just a warning)
openssl req -x509 -nodes -days "$CERT_DAYS" -newkey rsa:2048 \
    -keyout "$SSL_KEY" \
    -out "$SSL_CERT" \
    -subj "/C=US/ST=State/L=City/O=VCS/OU=AI-Agents/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,IP:13.217.22.125"

# Secure the private key
chmod 600 "$SSL_KEY"
chmod 644 "$SSL_CERT"

echo -e "${GREEN}  Certificate generated successfully${NC}"
echo "    Cert: $SSL_CERT"
echo "    Key:  $SSL_KEY"

# ── Step 3: Backup Current Nginx Config ─────────────────────────────────────
echo -e "${YELLOW}[3/5] Backing up current Nginx config...${NC}"

if [ -f "$NGINX_CONF_DST" ]; then
    BACKUP="$NGINX_CONF_DST.bak.$(date +%Y%m%d%H%M%S)"
    cp "$NGINX_CONF_DST" "$BACKUP"
    echo -e "${GREEN}  Backed up to: $BACKUP${NC}"
else
    echo -e "${CYAN}  No existing config to backup${NC}"
fi

# ── Step 4: Deploy SSL Nginx Config ─────────────────────────────────────────
echo -e "${YELLOW}[4/5] Deploying SSL Nginx config...${NC}"

if [ ! -f "$NGINX_CONF_SRC" ]; then
    echo -e "${RED}ERROR: Source config not found: $NGINX_CONF_SRC${NC}"
    exit 1
fi

cp "$NGINX_CONF_SRC" "$NGINX_CONF_DST"
ln -sf "$NGINX_CONF_DST" "$NGINX_CONF_ENABLED"

# Remove default site if it conflicts
rm -f /etc/nginx/sites-enabled/default

echo -e "${GREEN}  SSL config deployed${NC}"

# ── Step 5: Test and Reload Nginx ────────────────────────────────────────────
echo -e "${YELLOW}[5/5] Testing and reloading Nginx...${NC}"

if nginx -t 2>&1; then
    systemctl reload nginx
    echo -e "${GREEN}  Nginx reloaded successfully${NC}"
else
    echo -e "${RED}  Nginx config test FAILED!${NC}"
    echo -e "${YELLOW}  Restoring backup...${NC}"
    if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$NGINX_CONF_DST"
        nginx -t && systemctl reload nginx
        echo -e "${GREEN}  Backup restored${NC}"
    fi
    exit 1
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo -e "${GREEN}  Self-Signed SSL Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "  HTTPS (port 443): https://$DOMAIN"
echo "  HTTP redirect (port 80): http://$DOMAIN → https://$DOMAIN"
echo "  HTTP fallback (port 8000): still active"
echo ""
echo "  Test commands:"
echo "    curl -k https://$DOMAIN/gateway/health"
echo "    curl -k https://$DOMAIN/rag/health"
echo "    curl -k https://$DOMAIN/sql/health"
echo "    curl -k https://$DOMAIN/construction/health"
echo "    curl -k https://$DOMAIN/ingestion/health"
echo "    curl -k https://$DOMAIN/docqa/health"
echo ""
echo "  Certificate details:"
echo "    openssl x509 -in $SSL_CERT -text -noout | grep -A2 'Validity'"
echo ""
echo -e "${YELLOW}  NOTE: Self-signed certs cause browser warnings.${NC}"
echo -e "${YELLOW}  Run setup-ssl-letsencrypt.sh for production certificates.${NC}"
echo ""
