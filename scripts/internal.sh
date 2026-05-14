#!/bin/bash
# =============================================================================
# VPS Setup - Internal Functions
# =============================================================================
#
# Core infrastructure: update system, migration runner, logging, container
# detection helpers. Sourced by bootstrap.sh on shell login.
#
# Functions prefixed with _vps_ are internal (not user-facing).
# Functions prefixed with vps_ are user-facing management commands.
#
# =============================================================================

VPS_SETUP_DIR="/opt/vps-setup"
VPS_LOG_FILE="/var/log/vps-setup.log"
VPS_MIGRATION_TRACKER="/etc/vps-setup-migrations"

# Colors (only set if not already defined by another script)
RED="${RED:-\033[0;31m}"
GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"
NC="${NC:-\033[0m}"

# =============================================================================
# Logging
# =============================================================================

vps_log() {
    local message="${1:-}"
    local script_name="${2:-$(basename "${BASH_SOURCE[1]}" 2>/dev/null || echo "unknown")}"
    local commit_hash
    commit_hash=$(git -C "$VPS_SETUP_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local entry="[$timestamp] [$script_name] [$commit_hash] $message"

    # Append to log file (create if needed, use sudo if not root)
    if [ "$(id -u)" -eq 0 ]; then
        echo "$entry" >> "$VPS_LOG_FILE"
    else
        echo "$entry" | sudo tee -a "$VPS_LOG_FILE" > /dev/null
    fi
}

# =============================================================================
# Version Check
# =============================================================================

vps_check() {
    local quiet=false
    if [[ "${1:-}" == "--quiet" ]]; then
        quiet=true
    fi

    if [ ! -d "$VPS_SETUP_DIR/.git" ]; then
        if ! $quiet; then
            echo -e "${RED}[ERROR]${NC} VPS setup repo not found at $VPS_SETUP_DIR"
        fi
        return 1
    fi

    # Fetch latest (suppress output)
    sudo git -C "$VPS_SETUP_DIR" fetch origin main --quiet 2>/dev/null

    local local_hash remote_hash
    local_hash=$(git -C "$VPS_SETUP_DIR" rev-parse HEAD 2>/dev/null)
    remote_hash=$(git -C "$VPS_SETUP_DIR" rev-parse origin/main 2>/dev/null)

    if [ "$local_hash" != "$remote_hash" ]; then
        local behind
        behind=$(git -C "$VPS_SETUP_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
        echo -e "${YELLOW}[VPS Setup]${NC} Update available ($behind commit(s) behind). Run ${GREEN}vps_update${NC} to update."
        return 0
    fi

    if ! $quiet; then
        echo -e "${GREEN}[VPS Setup]${NC} Up to date."
    fi
    return 0
}

# =============================================================================
# Update System
# =============================================================================

vps_update() {
    # Escalate to root if needed (migrations require root for apt, sysctl, etc.)
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${BLUE}Updating VPS setup (requires sudo)...${NC}"
        sudo bash -c "source '$VPS_SETUP_DIR/scripts/internal.sh' && vps_update"
        # Re-source bootstrap to pick up any new functions
        source "$VPS_SETUP_DIR/scripts/bootstrap.sh"
        return $?
    fi

    echo -e "${BLUE}Pulling latest VPS setup...${NC}"
    vps_log "Starting update"

    if ! git -C "$VPS_SETUP_DIR" pull --ff-only origin main; then
        echo -e "${RED}[ERROR]${NC} Failed to pull updates. Check for local modifications."
        vps_log "Update failed: git pull error"
        return 1
    fi

    local new_hash
    new_hash=$(git -C "$VPS_SETUP_DIR" rev-parse --short HEAD 2>/dev/null)
    echo -e "${GREEN}Updated to${NC} $new_hash"

    # Run any new migrations
    vps_run_migrations

    vps_log "Update complete ($new_hash)"
    echo -e "${GREEN}[VPS Setup]${NC} Update complete."
}

# =============================================================================
# Migration Runner
# =============================================================================

vps_run_migrations() {
    # Escalate to root if needed
    if [ "$(id -u)" -ne 0 ]; then
        sudo bash -c "source '$VPS_SETUP_DIR/scripts/internal.sh' && vps_run_migrations"
        return $?
    fi

    local migrations_dir="$VPS_SETUP_DIR/migrations"
    local tracker="$VPS_MIGRATION_TRACKER"

    # Create tracker file if it doesn't exist
    touch "$tracker"

    if [ ! -d "$migrations_dir" ]; then
        return 0
    fi

    # Find migration files, sorted by name (timestamp prefix ensures order)
    local migration_files
    migration_files=$(find "$migrations_dir" -name '*.sh' -not -name '.gitkeep' | sort)

    if [ -z "$migration_files" ]; then
        return 0
    fi

    local ran=0
    local failed=0

    while IFS= read -r migration_file; do
        local filename
        filename=$(basename "$migration_file")

        # Skip if already recorded
        if grep -qF "$filename" "$tracker" 2>/dev/null; then
            continue
        fi

        echo -e "${BLUE}Running migration:${NC} $filename"
        vps_log "Migration start: $filename"

        # Source the migration file in a subshell-like context
        # Each migration must define a migration_up() function
        (
            # shellcheck source=/dev/null
            source "$migration_file"

            if ! declare -f migration_up > /dev/null 2>&1; then
                echo -e "${RED}[ERROR]${NC} Migration $filename does not define migration_up()"
                exit 1
            fi

            migration_up
        )

        if [ $? -eq 0 ]; then
            # Record successful migration: filename|timestamp
            echo "${filename}|$(date -Iseconds)" >> "$tracker"
            vps_log "Migration complete: $filename"
            echo -e "${GREEN}  Completed:${NC} $filename"
            ran=$((ran + 1))
        else
            echo -e "${RED}[ERROR]${NC} Migration failed: $filename"
            echo -e "${RED}  Fix the issue and run ${NC}vps_update${RED} again (it will retry).${NC}"
            vps_log "Migration FAILED: $filename"
            failed=$((failed + 1))
            # Stop on first failure - don't run subsequent migrations
            break
        fi
    done <<< "$migration_files"

    if [ $ran -gt 0 ]; then
        echo -e "${GREEN}Ran $ran migration(s) successfully.${NC}"
    fi
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Container Detection Helpers
# =============================================================================

# Walk up the directory tree to find a compose.yml file
_vps_traverse_to_compose() {
    local dir="${1:-$(pwd)}"
    local max_depth=30
    local depth=0

    while [ $depth -lt $max_depth ]; do
        if [ -f "$dir/compose.yml" ] || [ -f "$dir/docker-compose.yml" ]; then
            echo "$dir"
            return 0
        fi

        # Stop at filesystem root
        if [ "$dir" = "/" ]; then
            break
        fi

        dir=$(dirname "$dir")
        depth=$((depth + 1))
    done

    echo -e "${RED}[ERROR]${NC} No compose.yml found (searched $max_depth levels up)" >&2
    return 1
}

# Extract container prefix from compose.yml (e.g., "myapp" from "myapp-php")
_vps_get_container_prefix() {
    local compose_dir="${1:-}"

    # If no dir given, find it
    if [ -z "$compose_dir" ]; then
        compose_dir=$(_vps_traverse_to_compose) || return 1
    fi

    local compose_file="$compose_dir/compose.yml"
    if [ ! -f "$compose_file" ]; then
        compose_file="$compose_dir/docker-compose.yml"
    fi

    if [ ! -f "$compose_file" ]; then
        echo -e "${RED}[ERROR]${NC} No compose file found in $compose_dir" >&2
        return 1
    fi

    # Special case: proxy-nginx
    if grep -q 'proxy-nginx' "$compose_file" 2>/dev/null && [ "$(basename "$compose_dir")" = "proxy-nginx" ]; then
        echo "proxy-nginx"
        return 0
    fi

    # Extract container_name from compose.yml (first one found, strip the service suffix)
    local container_name
    container_name=$(grep 'container_name:' "$compose_file" | head -1 | sed 's/.*container_name:\s*//' | tr -d '"' | tr -d "'" | xargs)

    if [ -n "$container_name" ]; then
        # Strip the last -service part (e.g., "myapp-php" -> "myapp")
        local prefix="${container_name%-*}"
        echo "$prefix"
        return 0
    fi

    # Fallback: use directory name
    basename "$compose_dir"
}

# Execute a command in the PHP container
_vps_exec_php() {
    local prefix
    prefix=$(_vps_get_container_prefix) || return 1
    docker exec -u www-data "${prefix}-php" "$@"
}

# Execute an artisan command in the PHP container
_vps_artisan() {
    _vps_exec_php php artisan "$@"
}

# Execute artisan in a specific compose directory's project
_vps_artisan_in() {
    local compose_dir="$1"
    shift
    local prefix
    prefix=$(_vps_get_container_prefix "$compose_dir") || return 1
    docker exec -u www-data "${prefix}-php" php artisan "$@"
}
