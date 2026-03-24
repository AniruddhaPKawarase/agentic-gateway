#!/bin/bash
# =============================================================================
#  View logs for a VCS AI Agent service
# =============================================================================
#  Usage: bash logs.sh <agent-name> [--lines N]
#
#  Examples:
#    bash logs.sh rag              # Last 50 lines of RAG agent logs
#    bash logs.sh sql --lines 100  # Last 100 lines of SQL agent logs
#    bash logs.sh construction -f  # Follow construction agent logs (live)
#    bash logs.sh nginx            # Nginx access/error logs
# =============================================================================

set -euo pipefail

declare -A SERVICE_MAP=(
    ["rag"]="rag-agent"
    ["sql"]="sql-agent"
    ["construction"]="construction-agent"
    ["ingestion"]="ingestion-api"
    ["gateway"]="gateway-service"
)

if [ $# -eq 0 ]; then
    echo "Usage: bash logs.sh <agent-name> [--lines N | -f]"
    echo ""
    echo "Available agents: rag, sql, construction, ingestion, gateway, nginx"
    exit 1
fi

AGENT="$1"
shift

# Nginx has its own log files
if [ "$AGENT" == "nginx" ]; then
    echo "=== Nginx Access Log (last 50 lines) ==="
    sudo tail -n 50 /var/log/nginx/access.log 2>/dev/null || echo "(no access log)"
    echo ""
    echo "=== Nginx Error Log (last 20 lines) ==="
    sudo tail -n 20 /var/log/nginx/error.log 2>/dev/null || echo "(no error log)"
    exit 0
fi

if [ -z "${SERVICE_MAP[$AGENT]+x}" ]; then
    echo "Unknown agent: $AGENT"
    echo "Available: rag, sql, construction, ingestion, gateway, nginx"
    exit 1
fi

SVC="${SERVICE_MAP[$AGENT]}"

# Parse extra args
LINES=50
FOLLOW=false
while [ $# -gt 0 ]; do
    case "$1" in
        --lines) LINES="$2"; shift 2 ;;
        -f|--follow) FOLLOW=true; shift ;;
        *) shift ;;
    esac
done

if [ "$FOLLOW" = true ]; then
    echo "Following logs for ${SVC} (Ctrl+C to stop)..."
    sudo journalctl -u "$SVC" -f
else
    echo "=== Last $LINES lines from ${SVC} ==="
    sudo journalctl -u "$SVC" -n "$LINES" --no-pager
fi
