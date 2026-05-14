#!/bin/bash
# Graceful shutdown of a Docker Compose project
#
# For Laravel apps: puts app in maintenance mode, waits for running artisan
# processes to finish, checks for reserved queue jobs, then stops containers.
#
# Usage:
#   down          # Graceful shutdown
#   down -v       # Shutdown and remove volumes (wipe data)

down() {
    local compose_dir
    compose_dir=$(_vps_traverse_to_compose) || return 1
    local prefix
    prefix=$(_vps_get_container_prefix "$compose_dir") || return 1

    local compose_file="$compose_dir/compose.yml"
    if [ ! -f "$compose_file" ]; then
        compose_file="$compose_dir/docker-compose.yml"
    fi

    echo -e "${BLUE}Stopping${NC} $prefix..."

    # For proxy-nginx, just stop directly (no Laravel lifecycle)
    if [[ "$prefix" == "proxy-nginx" ]]; then
        docker compose -f "$compose_file" down "$@"
        echo -e "${GREEN}Stopped${NC} $prefix"
        return 0
    fi

    # Check if PHP container is running (if not, skip Laravel shutdown)
    if ! docker ps --format '{{.Names}}' | grep -q "^${prefix}-php$"; then
        echo -e "${YELLOW}PHP container not running, skipping graceful shutdown${NC}"
        docker compose -f "$compose_file" down "$@"
        echo -e "${GREEN}Stopped${NC} $prefix"
        return 0
    fi

    # --- Laravel-aware graceful shutdown ---

    # 1. Enter maintenance mode
    echo -e "${YELLOW}  Entering maintenance mode...${NC}"
    docker exec -u www-data "${prefix}-php" php artisan down --retry=60 2>/dev/null || true

    # 2. Wait for transient artisan processes to finish
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local procs
        procs=$(docker exec "${prefix}-php" pgrep -fa "artisan" 2>/dev/null \
            | grep -v "schedule:work\|queue:work\|queue:listen\|down" || true)

        if [ -z "$procs" ]; then
            break
        fi

        echo -e "${YELLOW}  Waiting for artisan processes (${timeout}s timeout, ${elapsed}s elapsed)...${NC}"
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [ $elapsed -ge $timeout ]; then
        echo -e "${YELLOW}  Timeout reached. Some processes may still be running.${NC}"
        echo -e "${YELLOW}  Proceeding with shutdown anyway.${NC}"
    fi

    # 3. Check Redis for reserved jobs (informational warning)
    if docker ps --format '{{.Names}}' | grep -q "^${prefix}-redis$"; then
        local reserved_keys
        reserved_keys=$(docker exec "${prefix}-redis" redis-cli KEYS "*queues*:reserved" 2>/dev/null || true)

        if [ -n "$reserved_keys" ]; then
            while IFS= read -r key; do
                [ -z "$key" ] && continue
                local count
                count=$(docker exec "${prefix}-redis" redis-cli ZCARD "$key" 2>/dev/null | tr -d '[:space:]' || echo "0")
                if [ "$count" != "0" ]; then
                    echo -e "${YELLOW}  Warning: $count reserved job(s) in $key${NC}"
                fi
            done <<< "$reserved_keys"
        fi
    fi

    # 4. Stop containers
    docker compose -f "$compose_file" down "$@"
    echo -e "${GREEN}Stopped${NC} $prefix"
}
