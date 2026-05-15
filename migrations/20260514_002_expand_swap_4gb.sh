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

    # Pre-flight: check available disk space (need ~4.5GB for swap + overhead)
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if [ "${available_gb:-0}" -lt 5 ]; then
        echo "Insufficient disk space: ${available_gb}GB available, need at least 5GB for 4GB swap." >&2
        return 1
    fi

    if [ -f /swapfile ]; then
        local current_size
        current_size=$(stat -c%s /swapfile 2>/dev/null || echo "0")

        if [ "$current_size" -ge "$SWAP_SIZE_BYTES" ]; then
            echo "Swap already >= 4GB ($(numfmt --to=iec "$current_size"))"
            # Ensure swap is active and persistent even if file already exists
            swapon --show | grep -q '^/swapfile' || swapon /swapfile
            grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
            return 0
        fi

        echo "Expanding swap from $(numfmt --to=iec "$current_size") to 4GB..."
        if ! swapoff /swapfile; then
            echo "Cannot resize: swap is in use and cannot be released. Free memory and retry." >&2
            return 1
        fi

        if ! fallocate -l 4G /swapfile 2>/dev/null; then
            dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress || {
                echo "Failed to create swap file (disk full?)" >&2
                return 1
            }
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "Swap expanded to 4GB"
        # Ensure swap persists across reboot
        grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    else
        echo "No swapfile found — creating 4GB swap..."

        if ! fallocate -l 4G /swapfile 2>/dev/null; then
            dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress || {
                echo "Failed to create swap file (disk full?)" >&2
                return 1
            }
        fi

        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile

        grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo "4GB swap created and enabled"
    fi
}
