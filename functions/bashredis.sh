#!/bin/bash
# Open an interactive shell in the Redis container (Alpine uses ash)

bashredis() {
    local prefix
    prefix=$(_vps_get_container_prefix) || return 1

    if [[ "$prefix" == "proxy-nginx" ]]; then
        echo -e "${RED}[ERROR]${NC} bashredis is not available for proxy-nginx"
        return 1
    fi

    docker exec -it "${prefix}-redis" /bin/ash 2>/dev/null \
        || docker exec -it "${prefix}-redis" /bin/sh
}
