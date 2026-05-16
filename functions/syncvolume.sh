#!/bin/bash
# Sync a Docker volume from a remote server to local using rsync
#
# Interactive tool that prompts for connection details and handles
# Docker volume path resolution and ownership preservation.
#
# Usage:
#   syncvolume

syncvolume() {
    echo -e "${BLUE}=== Docker Volume Sync ===${NC}"
    echo ""

    # Check dependencies
    if ! command -v rsync &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} rsync is not installed. Install with: sudo apt-get install -y rsync"
        return 1
    fi
    local has_sshpass=false
    if command -v sshpass &>/dev/null; then
        has_sshpass=true
    fi

    # Prompt for connection details
    read -rp "Remote server IP/hostname: " remote_host
    read -rp "Remote username [root]: " remote_user
    remote_user="${remote_user:-root}"
    local remote_pass=""
    if $has_sshpass; then
        read -rsp "SSH password (leave empty for key auth): " remote_pass
        echo ""
    else
        echo -e "${YELLOW}[INFO]${NC} sshpass not installed — using key auth (SSH will prompt if needed)."
    fi
    echo ""

    # Validate required inputs
    if [ -z "$remote_host" ]; then
        echo -e "${RED}[ERROR]${NC} Remote hostname is required."
        return 1
    fi

    read -rp "Remote path or volume name: " remote_path
    read -rp "Local path or volume name: " local_path

    if [ -z "$remote_path" ]; then
        echo -e "${RED}[ERROR]${NC} Remote path is required."
        return 1
    fi
    if [ -z "$local_path" ]; then
        echo -e "${RED}[ERROR]${NC} Local path is required."
        return 1
    fi

    # Resolve Docker volume names to paths
    if [[ "$remote_path" != /* ]]; then
        if [[ "$remote_path" == *..* ]] || [[ "$remote_path" == */* ]]; then
            echo -e "${RED}[ERROR]${NC} Invalid volume name: '$remote_path' (must not contain '..' or '/')"
            return 1
        fi
        remote_path="/var/lib/docker/volumes/${remote_path}/_data"
        echo -e "${BLUE}Resolved remote volume:${NC} $remote_path"
    fi

    if [[ "$local_path" != /* ]]; then
        if [[ "$local_path" == *..* ]] || [[ "$local_path" == */* ]]; then
            echo -e "${RED}[ERROR]${NC} Invalid volume name: '$local_path' (must not contain '..' or '/')"
            return 1
        fi
        local_path="/var/lib/docker/volumes/${local_path}/_data"
        echo -e "${BLUE}Resolved local volume:${NC} $local_path"
    fi

    # Reject dangerous paths
    for _path in "$remote_path" "$local_path"; do
        if [[ "$_path" == "/" ]] || [[ "$_path" == "//" ]]; then
            echo -e "${RED}[ERROR]${NC} Refusing to sync filesystem root. Check your paths."
            return 1
        fi
    done

    # Ensure trailing slash for rsync (sync contents, not directory itself)
    remote_path="${remote_path%/}/"
    local_path="${local_path%/}/"

    # Detect existing ownership before creating a missing target
    local existing_owner=""
    if sudo test -e "$local_path"; then
        existing_owner=$(sudo stat -c '%u:%g' "$local_path" 2>/dev/null || echo "")
    fi

    # Create local path if needed
    if ! sudo mkdir -p "$local_path"; then
        echo -e "${RED}[ERROR]${NC} Failed to create $local_path"
        return 1
    fi

    # Options
    echo ""
    echo "Options:"
    read -rp "Delete local files not on remote? [y/N]: " delete_extra
    echo ""

    # Build rsync command
    local rsync_opts="-avz --info=progress2 --stats"
    if [[ "${delete_extra,,}" == "y" ]]; then
        rsync_opts="$rsync_opts --delete"
    fi

    echo -e "${BLUE}Syncing...${NC}"
    echo "  From: ${remote_user}@${remote_host}:${remote_path}"
    echo "  To:   ${local_path}"
    echo ""

    # Run rsync with sudo (Docker volumes are owned by root)
    # Design: StrictHostKeyChecking=accept-new is intentional for this interactive admin
    # tool — it trusts on first connection and verifies on subsequent ones (TOFU model).
    # Full strict mode would require pre-distributing host keys, which is impractical for
    # a one-off migration tool where the operator confirms the remote host interactively.
    local rsync_exit_code
    if [ -n "$remote_pass" ] && command -v sshpass &>/dev/null; then
        sudo SSHPASS="$remote_pass" sshpass -e rsync $rsync_opts \
            -e "ssh -o StrictHostKeyChecking=accept-new" \
            "${remote_user}@${remote_host}:${remote_path}" "$local_path"
        rsync_exit_code=$?
    else
        sudo rsync $rsync_opts \
            -e "ssh -o StrictHostKeyChecking=accept-new" \
            "${remote_user}@${remote_host}:${remote_path}" "$local_path"
        rsync_exit_code=$?
    fi

    if [ $rsync_exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} rsync failed (exit code $rsync_exit_code)"
        echo -e "${RED}Skipping ownership changes to avoid corrupting incomplete data.${NC}"
        return 1
    fi

    echo ""
    echo -e "${GREEN}Sync complete.${NC}"

    # Ownership handling
    if [ -n "$existing_owner" ]; then
        echo ""
        echo "Current ownership: $existing_owner"
        echo ""
        echo "Ownership options:"
        echo "  1) Apply existing ownership ($existing_owner) to synced files"
        echo "  2) Skip (keep ownership from remote)"
        echo "  3) Custom (enter owner:group)"
        echo ""
        read -rp "Choice [2]: " chown_choice
        chown_choice="${chown_choice:-2}"

        case "$chown_choice" in
            1)
                echo -e "${BLUE}Applying ownership $existing_owner...${NC}"
                sudo chown -R "$existing_owner" "$local_path"
                echo -e "${GREEN}Done.${NC}"
                ;;
            2)
                echo "Skipped."
                ;;
            3)
                read -rp "Enter owner:group (e.g., www-data:www-data): " custom_owner
                if [[ "$custom_owner" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$ ]] || [[ "$custom_owner" =~ ^[0-9]+:[0-9]+$ ]]; then
                    echo -e "${BLUE}Applying ownership $custom_owner...${NC}"
                    sudo chown -R "$custom_owner" "$local_path"
                    echo -e "${GREEN}Done.${NC}"
                else
                    echo -e "${RED}Invalid format. Skipping.${NC}"
                fi
                ;;
        esac
    fi
}
