#!/bin/bash
# =============================================================================
#  VCS AI Agents — Let's Encrypt SSL Setup Script
# =============================================================================
#  Run this to set up HTTPS with a trusted Let's Encrypt certificate.
#    sudo bash setup-ssl-letsencrypt.sh
#
#  Prerequisites:
#    - DNS A record for ai.ifieldsmart.com → 13.217.22.125 (already done)
#    - Ports 80 and 443 open in firewall/security group
#    - Nginx already installed and running
#
#  What it does:
#    1. Installs Certbot + Nginx plugin
#    2. Backs up current Nginx config
#    3. Deploys Let's Encrypt Nginx config template
#    4. Obtains Let's Encrypt certificate via Certbot
#    5. Sets up auto-renewal (systemd timer)
#    6. Tests and reloads Nginx
#
#  After running:
#    - HTTPS with trusted cert at: https://ai.ifieldsmart.com (port 443)
#    - HTTP redirect at: http://ai.ifieldsmart.com (port 80 → 443)
#    - HTTP fallback at: http://<ip>:8000 (unchanged during transition)
#    - Auto-renewal active via systemd timer
# =============================================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
DOMAIN="ai.ifieldsmart.com"
EMAIL=""  # Set your email for Let's Encrypt notifications (optional)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATEWAY_DIR="$(dirname "$SCRIPT_DIR")"
NGINX_CONF_SRC="$GATEWAY_DIR/nginx/vcs-agents-letsencrypt.conf"
NGINX_CONF_DST="/etc/nginx/sites-available/vcs-agents"
NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/vcs-agents"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "  VCS AI Agents — Let's Encrypt SSL Setup"
echo "=========================================="
echo ""
echo "  Domain: $DOMAIN"
echo ""

# ── Check root ───────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run as root (sudo bash setup-ssl-letsencrypt.sh)${NC}"
    exit 1
fi

# ── Prompt for email (optional) ─────────────────────────────────────────────
if [ -z "$EMAIL" ]; then
    echo -e "${CYAN}  Let's Encrypt can send renewal/expiry notifications to your email.${NC}"
    read -p "  Enter email (or press Enter to skip): " EMAIL
    echo ""
fi

# ── Step 1: Install Certbot ─────────────────────────────────────────────────
echo -e "${YELLOW}[1/6] Installing Certbot...${NC}"

if command -v certbot &> /dev/null; then
    echo -e "${GREEN}  Certbot already installed: $(certbot --version 2>&1)${NC}"
else
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx
    echo -e "${GREEN}  Certbot installed successfully${NC}"
fi

# ── Step 2: Backup Current Nginx Config ─────────────────────────────────────
echo -e "${YELLOW}[2/6] Backing up current Nginx config...${NC}"

if [ -f "$NGINX_CONF_DST" ]; then
    BACKUP="$NGINX_CONF_DST.bak.$(date +%Y%m%d%H%M%S)"
    cp "$NGINX_CONF_DST" "$BACKUP"
    echo -e "${GREEN}  Backed up to: $BACKUP${NC}"
else
    echo -e "${CYAN}  No existing config to backup${NC}"
fi

# ── Step 3: Deploy Let's Encrypt Nginx Config ───────────────────────────────
echo -e "${YELLOW}[3/6] Deploying Let's Encrypt Nginx config...${NC}"

if [ ! -f "$NGINX_CONF_SRC" ]; then
    echo -e "${RED}ERROR: Source config not found: $NGINX_CONF_SRC${NC}"
    exit 1
fi

cp "$NGINX_CONF_SRC" "$NGINX_CONF_DST"
ln -sf "$NGINX_CONF_DST" "$NGINX_CONF_ENABLED"

# Remove default site if it conflicts
rm -f /etc/nginx/sites-enabled/default

# Create webroot for ACME challenges
mkdir -p /var/www/html/.well-known/acme-challenge

echo -e "${GREEN}  Config deployed${NC}"

# ── Step 4: Obtain Let's Encrypt Certificate ────────────────────────────────
echo -e "${YELLOW}[4/6] Obtaining Let's Encrypt certificate...${NC}"

# We must first reload Nginx so the port 80 block (with ACME challenge location) is active
echo "  Reloading Nginx to enable ACME challenge endpoint..."
if nginx -t 2>&1 && systemctl reload nginx; then
    echo -e "${GREEN}  Nginx ready for ACME challenge${NC}"
else
    echo -e "${RED}  Nginx config test failed — cannot proceed with certbot${NC}"
    exit 1
fi

# Build certbot command — use certonly + webroot to avoid certbot modifying our config
# The --nginx plugin rewrites Nginx config in-place, which would corrupt our hand-crafted config
CERTBOT_CMD="certbot certonly --webroot -w /var/www/html -d $DOMAIN --non-interactive --agree-tos"

if [ -n "$EMAIL" ]; then
    CERTBOT_CMD="$CERTBOT_CMD --email $EMAIL"
else
    CERTBOT_CMD="$CERTBOT_CMD --register-unsafely-without-email"
fi

echo "  Running: $CERTBOT_CMD"
echo ""

if $CERTBOT_CMD; then
    echo -e "${GREEN}  Certificate obtained successfully!${NC}"
else
    echo -e "${RED}  Certbot failed to obtain certificate!${NC}"
    echo ""
    echo "  Common causes:"
    echo "    - DNS A record not pointing to this server"
    echo "    - Port 80 blocked by firewall/security group"
    echo "    - Domain already has a certificate (use certbot renew)"
    echo ""
    echo -e "${YELLOW}  Restoring backup...${NC}"
    if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$NGINX_CONF_DST"
        nginx -t && systemctl reload nginx
        echo -e "${GREEN}  Backup restored${NC}"
    fi
    exit 1
fi

# ── Step 5: Set Up Auto-Renewal ─────────────────────────────────────────────
echo -e "${YELLOW}[5/6] Setting up auto-renewal...${NC}"

# Certbot on Ubuntu typically installs a systemd timer automatically
if systemctl list-timers | grep -q certbot; then
    echo -e "${GREEN}  Certbot systemd timer already active${NC}"
else
    # Create a deploy hook script (Certbot-recommended approach, avoids cron quoting issues)
    HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
    mkdir -p "$HOOK_DIR"
    cat > "$HOOK_DIR/nginx-reload.sh" << 'HOOKEOF'
#!/bin/bash
# Reload Nginx after successful certificate renewal
nginx -t && systemctl reload nginx
HOOKEOF
    chmod +x "$HOOK_DIR/nginx-reload.sh"

    # Add cron job for renewal (hook handles Nginx reload automatically)
    CRON_CMD='0 0,12 * * * certbot renew --quiet'
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo -e "${GREEN}  Cron job added for auto-renewal (twice daily)${NC}"
        echo -e "${GREEN}  Deploy hook installed at $HOOK_DIR/nginx-reload.sh${NC}"
    else
        echo -e "${GREEN}  Cron job for certbot already exists${NC}"
    fi
fi

# ── Step 6: Test and Verify ─────────────────────────────────────────────────
echo -e "${YELLOW}[6/6] Testing configuration...${NC}"

# Test Nginx config
if nginx -t 2>&1; then
    systemctl reload nginx
    echo -e "${GREEN}  Nginx reloaded successfully${NC}"
else
    echo -e "${RED}  Nginx config test FAILED after certbot!${NC}"
    exit 1
fi

# Test renewal (dry run)
echo ""
echo -e "${CYAN}  Running renewal dry-run...${NC}"
if certbot renew --dry-run 2>&1; then
    echo -e "${GREEN}  Renewal dry-run passed${NC}"
else
    echo -e "${YELLOW}  Renewal dry-run had issues (check certbot logs)${NC}"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo -e "${GREEN}  Let's Encrypt SSL Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "  HTTPS (port 443): https://$DOMAIN"
echo "  HTTP redirect (port 80): http://$DOMAIN → https://$DOMAIN"
echo "  HTTP fallback (port 8000): still active (remove after transition)"
echo ""
echo "  Test commands:"
echo "    curl https://$DOMAIN/gateway/health"
echo "    curl https://$DOMAIN/rag/health"
echo "    curl https://$DOMAIN/sql/health"
echo "    curl https://$DOMAIN/construction/health"
echo "    curl https://$DOMAIN/ingestion/health"
echo "    curl https://$DOMAIN/docqa/health"
echo ""
echo "  Certificate info:"
echo "    sudo certbot certificates"
echo ""
echo "  Auto-renewal status:"
echo "    systemctl status certbot.timer"
echo "    sudo certbot renew --dry-run"
echo ""
echo "  Next steps:"
echo "    1. Verify all endpoints work over HTTPS"
echo "    2. Test SSE streaming endpoints"
echo "    3. Update frontend/client URLs to https://$DOMAIN"
echo "    4. After 24-48h monitoring, block port 8000:"
echo "       sudo ufw deny 8000/tcp"
echo ""
