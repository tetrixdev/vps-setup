#!/bin/bash
# =============================================================================
# VPS Setup - Bootstrap (sourced on shell login via .bashrc)
# =============================================================================
#
# Loads all VPS operations functions and shows update status.
#
# =============================================================================

VPS_SETUP_DIR="/opt/vps-setup"

# Guard: only source once per shell session
if [ -n "${_VPS_BOOTSTRAP_LOADED:-}" ]; then
    return 0 2>/dev/null || true
fi
_VPS_BOOTSTRAP_LOADED=1

# Guard: skip if repo doesn't exist
if [ ! -d "$VPS_SETUP_DIR/scripts" ]; then
    return 0 2>/dev/null || true
fi

# Source internal functions (update, check, migrations, helpers)
# shellcheck source=/dev/null
source "$VPS_SETUP_DIR/scripts/internal.sh"

# Source all user-facing functions
for _vps_func_file in "$VPS_SETUP_DIR/functions/"*.sh; do
    if [ -f "$_vps_func_file" ]; then
        # shellcheck source=/dev/null
        source "$_vps_func_file"
    fi
done
unset _vps_func_file

# Show heartbeat status
if [ -f /etc/vps-setup-heartbeat.conf ]; then
    if grep -q '^HEARTBEAT_URL=' /etc/vps-setup-heartbeat.conf 2>/dev/null; then
        : # Heartbeat configured, all good
    else
        echo -e "${YELLOW}[VPS Setup]${NC} Heartbeat not connected. Edit /etc/vps-setup-heartbeat.conf to enable monitoring."
    fi
fi

# Check for updates (background, non-blocking)
# Only runs if this is an interactive login shell
if [[ $- == *i* ]]; then
    vps_check --quiet
fi
