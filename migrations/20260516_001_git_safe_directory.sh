#!/bin/bash
# Migration: Mark /opt/vps-setup as a safe git directory for all users
#
# setup.sh clones /opt/vps-setup as root, but operators run git-based commands
# (notably vps_check) as the admin user. Git refuses to operate on a repository
# owned by a different user ("dubious ownership") unless the path is explicitly
# trusted. This registers it system-wide (/etc/gitconfig) so vps_check works for
# the admin user. vps_update was unaffected — it escalates to root, who owns the
# repo — but vps_check runs rev-parse as the calling user.

migration_up() {
    local repo="/opt/vps-setup"

    # Idempotency: skip if already trusted (avoids duplicate config entries)
    if git config --system --get-all safe.directory 2>/dev/null | grep -qxF "$repo"; then
        echo "Git safe.directory already configured for $repo"
        return 0
    fi

    if ! git config --system --add safe.directory "$repo"; then
        echo "Failed to register $repo as a safe git directory" >&2
        return 1
    fi

    echo "Registered $repo as a safe git directory (system-wide)"
}
