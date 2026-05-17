#!/bin/bash
# Migration: Deploy the Claude Code context file (~admin/CLAUDE.md)
#
# Initial rollout only. The actual rendering lives in _vps_sync_claude_context()
# in scripts/internal.sh, which vps_update calls on every run to keep the managed
# block in sync. This migration just triggers that function once, so existing
# servers get the file on their first vps_update after this change.
#
# Idempotent: _vps_sync_claude_context() creates the file if missing, replaces
# only the managed marker block if present, and preserves operator content below
# the end marker.

migration_up() {
    local VPS_SETUP_DIR="${VPS_SETUP_DIR:-/opt/vps-setup}"

    # shellcheck source=/dev/null
    source "$VPS_SETUP_DIR/scripts/internal.sh"

    if ! declare -f _vps_sync_claude_context > /dev/null 2>&1; then
        echo "_vps_sync_claude_context() not found in internal.sh" >&2
        return 1
    fi

    _vps_sync_claude_context
}
