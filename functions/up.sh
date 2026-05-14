#!/bin/bash
# Start a Docker Compose project (with project detection)

up() {
    local compose_dir
    compose_dir=$(_vps_traverse_to_compose) || return 1
    local prefix
    prefix=$(_vps_get_container_prefix "$compose_dir") || return 1

    echo -e "${BLUE}Starting${NC} $prefix..."

    if [[ "$prefix" == "proxy-nginx" ]]; then
        docker compose -f "$compose_dir/compose.yml" up -d
    elif [[ -f "$compose_dir/up.sh" ]]; then
        # Delegate to project-level up.sh if it exists (e.g., slim-docker-laravel deploy script)
        bash "$compose_dir/up.sh"
    else
        docker compose -f "$compose_dir/compose.yml" pull 2>/dev/null || true
        docker compose -f "$compose_dir/compose.yml" up -d
    fi

    echo -e "${GREEN}Started${NC} $prefix"
}
