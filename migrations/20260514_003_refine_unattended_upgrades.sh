#!/bin/bash
# Migration: Refine unattended-upgrades configuration
#
# Improvements over the initial setup.sh configuration:
# - Uses a 52-* override file (sorts after Ubuntu's default 50-*) to avoid
#   conflicts with distro defaults.
# - Enables ESM Apps and ESM Infra security origins for broader coverage.
# - Enables automatic reboot at 4:00 AM when kernel updates require it.
#   (Personal servers can reboot unattended; production servers should not.)
# - Removes unused kernel packages and dependencies.
# - Installs update-notifier-common for /var/run/reboot-required tracking.
# - Validates config with a dry-run before finalizing.

migration_up() {
    # Install reboot-required tracking
    apt-get install -y -qq update-notifier-common 2>/dev/null || true

    # Write our override config (52-* sorts AFTER Ubuntu's default 50-*)
    cat > /etc/apt/apt.conf.d/52unattended-upgrades-vps-setup << 'EOF'
// VPS Setup unattended-upgrades configuration
// Overrides/extends defaults from 50unattended-upgrades

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Auto-reboot at 4:00 AM when required (e.g., kernel updates)
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";

// Clean up unused kernels and dependencies
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

    # Remove our old 50-* file if it exists and was written by setup.sh
    # (Check for our marker: AutoFixInterruptedDpkg, which Ubuntu's default doesn't have)
    if [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
        if grep -q 'AutoFixInterruptedDpkg' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null; then
            rm -f /etc/apt/apt.conf.d/50unattended-upgrades
            echo "Removed old setup.sh unattended-upgrades config (replaced by 52-* override)"
        fi
    fi

    # Ensure auto-upgrades schedule is correct
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF

    # Validate configuration
    if command -v unattended-upgrade &>/dev/null; then
        local dry_run_output
        dry_run_output=$(unattended-upgrade --dry-run 2>&1 || true)
        if echo "$dry_run_output" | grep -qi "error"; then
            echo "Warning: unattended-upgrades dry-run reported errors:"
            echo "$dry_run_output" | grep -i "error" | head -5
        else
            echo "Unattended-upgrades config validated (dry-run passed)"
        fi
    fi

    # Ensure all timers are enabled
    systemctl enable apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service 2>/dev/null || true
    systemctl start apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

    echo "Unattended-upgrades refined: 52-* override, auto-reboot at 04:00, ESM security origins"
}
