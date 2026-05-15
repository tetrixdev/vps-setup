#!/bin/bash
# Open an interactive shell in the PHP container (as www-data)

bashphp() {
    local prefix
    prefix=$(_vps_get_container_prefix) || return 1

    if [[ "$prefix" == "proxy-nginx" ]]; then
        echo -e "${RED}[ERROR]${NC} bashphp is not available for proxy-nginx"
        return 1
    fi

    if ! docker ps --format '{{.Names}}' | grep -q "^${prefix}-php$"; then
        echo -e "${RED}[ERROR]${NC} Container '${prefix}-php' is not running. Try 'up' first."
        return 1
    fi

    docker exec -it -u www-data "${prefix}-php" /bin/bash 2>/dev/null \
        || docker exec -it -u www-data "${prefix}-php" /bin/sh
}
