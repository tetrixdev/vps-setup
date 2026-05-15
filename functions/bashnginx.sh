#!/bin/bash
# Open an interactive shell in the nginx container

bashnginx() {
    local prefix
    prefix=$(_vps_get_container_prefix) || return 1

    if [[ "$prefix" == "proxy-nginx" ]]; then
        # proxy-nginx is a standalone container, not prefixed
        docker exec -it proxy-nginx /bin/bash 2>/dev/null \
            || docker exec -it proxy-nginx /bin/sh
    else
        if ! docker ps --format '{{.Names}}' | grep -q "^${prefix}-nginx$"; then
            echo -e "${RED}[ERROR]${NC} Container '${prefix}-nginx' is not running. Try 'up' first."
            return 1
        fi
        docker exec -it "${prefix}-nginx" /bin/bash 2>/dev/null \
            || docker exec -it "${prefix}-nginx" /bin/sh
    fi
}
