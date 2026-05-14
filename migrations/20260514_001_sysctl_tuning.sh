#!/bin/bash
# Migration: Configure kernel parameters for better I/O and memory behavior
#
# - vm.dirty_ratio=15: Limits dirty page cache to 15% of RAM before forcing
#   synchronous writes. Prevents I/O storms where the kernel accumulates too
#   much dirty data and then stalls while flushing it all at once.
# - vm.dirty_background_ratio=5: Background flushing starts at 5% of RAM,
#   keeping the dirty page backlog small for smoother I/O.
# - vm.swappiness=10: Prefer keeping data in RAM. Only swap when memory is
#   actually tight, not proactively.

migration_up() {
    local SYSCTL_FILE="/etc/sysctl.d/99-vps-setup.conf"

    # Create or update our sysctl config
    cat > "$SYSCTL_FILE" << 'EOF'
# VPS Setup kernel tuning
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.swappiness = 10
EOF

    if ! sysctl -p "$SYSCTL_FILE" > /dev/null; then
        echo "Failed to apply sysctl settings from $SYSCTL_FILE" >&2
        return 1
    fi

    # Clean up old swappiness entry from /etc/sysctl.conf (written by setup.sh v1)
    if grep -q '^vm\.swappiness=10$' /etc/sysctl.conf 2>/dev/null; then
        sed -i '/^vm\.swappiness=10$/d' /etc/sysctl.conf
        echo "Cleaned up legacy swappiness entry from /etc/sysctl.conf"
    fi

    echo "Kernel parameters configured: dirty_ratio=15, dirty_background_ratio=5, swappiness=10"
}
