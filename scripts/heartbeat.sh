#!/bin/bash
# =============================================================================
# VPS Setup - Heartbeat
# =============================================================================
#
# Collects server state and POSTs it to a monitoring endpoint.
# Runs every 15 minutes via cron (installed by migration).
#
# Configuration: /etc/vps-setup-heartbeat.conf
#   HEARTBEAT_URL=https://your-server.com/api/heartbeat
#   HEARTBEAT_TOKEN=your-secret-token
#
# =============================================================================

set -euo pipefail

VPS_SETUP_DIR="/opt/vps-setup"
HEARTBEAT_CONFIG="/etc/vps-setup-heartbeat.conf"
LOG_FILE="/var/log/vps-setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [heartbeat] $1" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
HEARTBEAT_URL=""
HEARTBEAT_TOKEN=""

if [ -f "$HEARTBEAT_CONFIG" ]; then
    # Safe parsing: only read KEY=VALUE lines, no shell execution
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        [[ "$line" != *=* ]] && continue

        key="${line%%=*}"
        value="${line#*=}"

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^["'\''"]//;s/["'\''"]$//')

        case "$key" in
            HEARTBEAT_URL) HEARTBEAT_URL="$value" ;;
            HEARTBEAT_TOKEN) HEARTBEAT_TOKEN="$value" ;;
        esac
    done < "$HEARTBEAT_CONFIG"
fi

if [ -z "$HEARTBEAT_URL" ]; then
    # Not configured - skip silently (this is expected on fresh installs)
    exit 0
fi

# ---------------------------------------------------------------------------
# Collect VPS Setup info
# ---------------------------------------------------------------------------
VPS_COMMIT=$(git -C "$VPS_SETUP_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
VPS_BRANCH=$(git -C "$VPS_SETUP_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Check if update is available
VPS_UPDATE_AVAILABLE="false"
if git -C "$VPS_SETUP_DIR" fetch origin main --quiet 2>/dev/null; then
    local_hash=$(git -C "$VPS_SETUP_DIR" rev-parse HEAD 2>/dev/null || echo "")
    remote_hash=$(git -C "$VPS_SETUP_DIR" rev-parse origin/main 2>/dev/null || echo "")
    if [ -n "$local_hash" ] && [ -n "$remote_hash" ] && [ "$local_hash" != "$remote_hash" ]; then
        VPS_UPDATE_AVAILABLE="true"
    fi
fi

# ---------------------------------------------------------------------------
# Collect system info
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname)
OS_INFO=""
if [ -f /etc/os-release ]; then
    OS_INFO=$(grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release | tr '\n' '|' | sed 's/|$//')
fi

# Reboot required?
REBOOT_REQUIRED="false"
REBOOT_PACKAGES=""
if [ -f /var/run/reboot-required ]; then
    REBOOT_REQUIRED="true"
    if [ -f /var/run/reboot-required.pkgs ]; then
        REBOOT_PACKAGES=$(cat /var/run/reboot-required.pkgs | tr '\n' ',' | sed 's/,$//')
    fi
fi

# Unattended upgrades status
UNATTENDED_ENABLED="false"
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    UNATTENDED_ENABLED="true"
fi

# ---------------------------------------------------------------------------
# Collect application data
# ---------------------------------------------------------------------------
APPS_JSON="[]"
# Resolve docker-apps directory (heartbeat runs as root via cron, so $HOME=/root)
# Read admin username from setup config, fall back to 'admin'
ADMIN_HOME=""
if [ -f /etc/vps-setup.conf ]; then
    ADMIN_HOME=$(getent passwd admin 2>/dev/null | cut -d: -f6 || echo "")
fi
DOCKER_APPS_DIR="${ADMIN_HOME:-/home/admin}/docker-apps"

# Design: The JSON array is built manually with comma-tracking and bracket-echoing
# rather than using `jq -s`. This is intentional — the approach works, the jq safety
# net (| jq -c '.') at the end catches malformed output, and each app's jq call handles
# its own data. Refactoring to jq -s would be polish without functional benefit.
if [ -d "$DOCKER_APPS_DIR" ]; then
    APPS_JSON=$(
        echo "["
        first=true
        for app_dir in "$DOCKER_APPS_DIR"/*/; do
            [ -d "$app_dir" ] || continue
            app_name=$(basename "$app_dir")

            # Get container statuses
            containers_json="[]"
            compose_file=""
            if [ -f "${app_dir}compose.yml" ]; then
                compose_file="${app_dir}compose.yml"
            elif [ -f "${app_dir}docker-compose.yml" ]; then
                compose_file="${app_dir}docker-compose.yml"
            fi
            if [ -n "$compose_file" ]; then
                containers_json=$(docker compose -f "$compose_file" ps --format json 2>/dev/null | jq -s '.' 2>/dev/null || echo "[]")
            fi

            # Get version from .env or compose image tag
            app_version="unknown"
            if [ -f "$app_dir/.env" ]; then
                extracted=$(grep -E '^IMAGE_TAG=' "$app_dir/.env" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' || true)
                [ -n "$extracted" ] && app_version="$extracted"
            fi

            if ! $first; then echo ","; fi
            first=false

            jq -n \
                --arg name "$app_name" \
                --arg version "$app_version" \
                --argjson containers "$containers_json" \
                '{name: $name, version: $version, containers: $containers}'
        done
        echo "]"
    ) 2>/dev/null || APPS_JSON="[]"

    # Validate JSON
    APPS_JSON=$(echo "$APPS_JSON" | jq -c '.' 2>/dev/null || echo "[]")
fi

# Design: proxy_config was intentionally removed from the heartbeat payload.
# Sending the full nginx config disclosed internal server topology (upstream names,
# internal IPs, routing rules) to the monitoring endpoint on every heartbeat.

# ---------------------------------------------------------------------------
# Build payload
# ---------------------------------------------------------------------------
PAYLOAD=$(jq -n \
    --arg hostname "$HOSTNAME" \
    --arg os_info "$OS_INFO" \
    --arg vps_commit "$VPS_COMMIT" \
    --arg vps_branch "$VPS_BRANCH" \
    --arg vps_update_available "$VPS_UPDATE_AVAILABLE" \
    --arg reboot_required "$REBOOT_REQUIRED" \
    --arg reboot_packages "$REBOOT_PACKAGES" \
    --arg unattended_enabled "$UNATTENDED_ENABLED" \
    --argjson apps "$APPS_JSON" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        hostname: $hostname,
        os_info: $os_info,
        vps_setup: {
            commit: $vps_commit,
            branch: $vps_branch,
            update_available: ($vps_update_available == "true")
        },
        system: {
            reboot_required: ($reboot_required == "true"),
            reboot_packages: $reboot_packages,
            unattended_upgrades_enabled: ($unattended_enabled == "true")
        },
        apps: $apps,
        timestamp: $timestamp
    }'
)

# ---------------------------------------------------------------------------
# Send heartbeat
# ---------------------------------------------------------------------------
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
    -X POST "$HEARTBEAT_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $HEARTBEAT_TOKEN" \
    -d "$PAYLOAD" \
    --connect-timeout 10 \
    --max-time 30 \
    2>/dev/null || echo "000")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    log "Heartbeat sent successfully (HTTP $HTTP_CODE)"
else
    log "Heartbeat failed (HTTP $HTTP_CODE)"
fi
