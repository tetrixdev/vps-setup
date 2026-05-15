#!/bin/bash
# Open an interactive shell in the PostgreSQL container

bashpostgres() {
    local prefix
    prefix=$(_vps_get_container_prefix) || return 1

    if [[ "$prefix" == "proxy-nginx" ]]; then
        echo -e "${RED}[ERROR]${NC} bashpostgres is not available for proxy-nginx"
        return 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "^${prefix}-postgres$"; then
        echo -e "${RED}[ERROR]${NC} Container '${prefix}-postgres' is not running. Try 'up' first."
        return 1
    fi

    docker exec -it "${prefix}-postgres" /bin/bash 2>/dev/null \
        || docker exec -it "${prefix}-postgres" /bin/sh
}
