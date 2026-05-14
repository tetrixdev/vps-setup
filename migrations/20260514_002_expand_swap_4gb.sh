#!/bin/bash
# Migration: Expand swap to 4GB
#
# 4GB swap is the standard regardless of server RAM. Rationale:
# - Swap exists as a safety buffer, not as a performance feature.
# - If the server regularly uses swap, the correct fix is upgrading RAM.
# - A smaller swap risks OOM-killing containers under brief memory spikes.
# - A larger swap delays OOM alerts, masking real memory pressure.
# - 4GB provides adequate buffer for transient spikes without hiding problems.

migration_up() {
    local SWAP_SIZE_BYTES=$((4 * 1024 * 1024 * 1024))  # 4GB in bytes

    if [ -f /swapfile ]; then
        local current_size
        current_size=$(stat -c%s /swapfile 2>/dev/null || echo "0")

        if [ "$current_size" -ge "$SWAP_SIZE_BYTES" ]; then
            echo "Swap already >= 4GB ($(numfmt --to=iec "$current_size")), skipping"
            return 0
        fi

        echo "Expanding swap from $(numfmt --to=iec "$current_size") to 4GB..."
        swapoff /swapfile

        if ! fallocate -l 4G /swapfile 2>/dev/null; then
            dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "Swap expanded to 4GB"
    else
        echo "No swapfile found — creating 4GB swap..."

        if ! fallocate -l 4G /swapfile 2>/dev/null; then
            dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile

        grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "4GB swap created and enabled"
    fi
}
