#!/bin/bash
# Configure GitHub integration for the current user from a single token
#
# A GitHub token (PAT) authenticates all three of: git push over HTTPS, the
# gh CLI, and docker pulls from ghcr.io. ghsetup wires up all of them, plus the
# git author identity. It is run by setup.sh on a fresh server and can be run
# again at any time.
#
# Inputs (environment): GITHUB_TOKEN or GH_TOKEN, GIT_NAME, GIT_EMAIL.
# Missing values are prompted for, unless --noninteractive is passed (then they
# are skipped). The token needs the 'repo', 'read:packages' and 'read:org'
# scopes for git, ghcr and a stored gh login respectively.

ghsetup() {
    local interactive=true
    [[ "${1:-}" == "--noninteractive" ]] && interactive=false

    if ! command -v gh > /dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} gh is not installed. Run ${GREEN}vps_update${NC} first."
        return 1
    fi

    local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
    local name="${GIT_NAME:-}"
    local email="${GIT_EMAIL:-}"

    # gh auth login refuses to run while GH_TOKEN/GITHUB_TOKEN is in the
    # environment — the token is captured above, so clear them now.
    unset GITHUB_TOKEN GH_TOKEN

    if [ -z "$token" ] && $interactive && [ -e /dev/tty ]; then
        read -rsp "GitHub token (PAT — scopes: repo, read:packages, read:org): " token < /dev/tty
        echo
    fi
    if [ -z "$token" ]; then
        echo -e "${YELLOW}[ghsetup]${NC} No GitHub token provided — nothing to configure."
        echo -e "          Re-run ${GREEN}ghsetup${NC} with a token to connect git, gh and ghcr.io."
        return 1
    fi

    # Resolve the GitHub account the token belongs to (also validates the token)
    local ghuser
    ghuser=$(GH_TOKEN="$token" gh api user --jq '.login' 2>/dev/null)
    if [ -z "$ghuser" ]; then
        echo -e "${RED}[ERROR]${NC} GitHub rejected the token (could not read the account)."
        return 1
    fi
    echo -e "${BLUE}[ghsetup]${NC} Token belongs to GitHub account '${ghuser}'."

    if [ -z "$name" ] && $interactive && [ -e /dev/tty ]; then
        read -rp "Git author name [$ghuser]: " name < /dev/tty
        name="${name:-$ghuser}"
    fi
    if [ -z "$email" ] && $interactive && [ -e /dev/tty ]; then
        read -rp "Git author email: " email < /dev/tty
    fi

    # 1. Git author identity
    if [ -n "$name" ]; then
        git config --global user.name "$name"
        echo -e "${GREEN}[git]${NC} user.name = $name"
    fi
    if [ -n "$email" ]; then
        git config --global user.email "$email"
        echo -e "${GREEN}[git]${NC} user.email = $email"
    fi

    # 2. Git push credentials over HTTPS (store helper + ~/.git-credentials)
    git config --global credential.helper store
    local credfile="$HOME/.git-credentials"
    local tmp
    tmp=$(mktemp)
    grep -v '@github\.com' "$credfile" 2>/dev/null > "$tmp" || true
    echo "https://${ghuser}:${token}@github.com" >> "$tmp"
    mv "$tmp" "$credfile"
    chmod 600 "$credfile"
    echo -e "${GREEN}[git]${NC} HTTPS credentials stored for github.com"

    # 3. GitHub CLI
    if printf '%s' "$token" | gh auth login --hostname github.com --with-token 2>/dev/null; then
        echo -e "${GREEN}[gh]${NC} gh CLI authenticated."
    else
        echo -e "${YELLOW}[gh]${NC} gh stored login skipped — token lacks the 'read:org' scope."
        echo -e "         gh still works when ${GREEN}GH_TOKEN${NC} is set in the environment."
    fi

    # 4. Docker / GitHub Container Registry
    if command -v docker > /dev/null 2>&1; then
        if printf '%s' "$token" | docker login ghcr.io -u "$ghuser" --password-stdin > /dev/null 2>&1; then
            echo -e "${GREEN}[docker]${NC} logged in to ghcr.io"
        else
            echo -e "${YELLOW}[docker]${NC} ghcr.io login failed — token may lack 'read:packages'."
        fi
    fi

    echo -e "${GREEN}[ghsetup]${NC} GitHub integration configured."
}
