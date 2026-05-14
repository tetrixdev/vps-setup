#!/bin/bash
# Open an interactive shell in the PHP container (as www-data)

bashphp() {
    local prefix
    prefix=$(_vps_get_container_prefix) || return 1

    if [[ "$prefix" == "proxy-nginx" ]]; then
        echo -e "${RED}[ERROR]${NC} bashphp is not available for proxy-nginx"
        return 1
    fi

    docker exec -it -u www-data "${prefix}-php" /bin/bash
}
