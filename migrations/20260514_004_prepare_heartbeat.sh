#!/bin/bash
# Migration: Prepare heartbeat monitoring infrastructure
#
# Installs a cron job that runs heartbeat.sh every 15 minutes and creates
# a config template. The heartbeat is inactive until a monitoring endpoint
# is configured in /etc/vps-setup-heartbeat.conf.

migration_up() {
    local HEARTBEAT_CONFIG="/etc/vps-setup-heartbeat.conf"
    local VPS_SETUP_DIR="/opt/vps-setup"

    # Create heartbeat config template (only if it doesn't exist)
    if [ ! -f "$HEARTBEAT_CONFIG" ]; then
        cat > "$HEARTBEAT_CONFIG" << 'EOF'
# VPS Setup Heartbeat Configuration
#
# Uncomment and fill in these values to enable server monitoring.
# The heartbeat script runs every 15 minutes and sends server state
# (container statuses, OS info, update availability) to the endpoint.
#
# HEARTBEAT_URL=https://your-monitoring-server.com/api/heartbeat
# HEARTBEAT_TOKEN=your-secret-token
EOF
        echo "Heartbeat config template created at $HEARTBEAT_CONFIG"
    fi

    # Install cron job (every 15 minutes)
    local CRON_LINE="*/15 * * * * /bin/bash $VPS_SETUP_DIR/scripts/heartbeat.sh >> /var/log/vps-setup.log 2>&1"

    # Add to root crontab (replace any existing heartbeat entry)
    (crontab -l 2>/dev/null | grep -v "vps-setup.*heartbeat"; echo "$CRON_LINE") | crontab -

    echo "Heartbeat cron job installed (every 15 minutes)"
    echo "Configure $HEARTBEAT_CONFIG to connect to a monitoring endpoint"
}
