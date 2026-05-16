#!/bin/bash
# Start a Docker Compose project (with project detection)

up() {
    local compose_dir
    compose_dir=$(_vps_traverse_to_compose) || return 1
    local prefix
    prefix=$(_vps_get_container_prefix "$compose_dir") || return 1

    local compose_file
    compose_file=$(_vps_find_compose_file "$compose_dir") || return 1

    echo -e "${BLUE}Starting${NC} $prefix..."

    if [[ "$prefix" == "proxy-nginx" ]]; then
        docker compose -f "$compose_file" up -d || return 1
    elif [[ -f "$compose_dir/up.sh" ]]; then
        # Delegate to project-level up.sh if it exists (e.g., slim-docker-laravel deploy script)
        (cd "$compose_dir" && bash "./up.sh") || return 1
    else
        if ! docker compose -f "$compose_file" pull 2>&1; then
            echo -e "${YELLOW}[WARN]${NC} Image pull failed — starting with cached images."
        fi
        docker compose -f "$compose_file" up -d || return 1
    fi

    echo -e "${GREEN}Started${NC} $prefix"
}
