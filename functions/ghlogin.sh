#!/bin/bash
# Authenticate the GitHub CLI (gh), non-interactively when a token is available
#
# gh auth is per-user and interactive by nature, so it cannot be a migration.
# This helper makes it a one-word manual step: it reuses a token that is already
# available (the $GH_TOKEN env var, or the github.com token git stores in
# ~/.git-credentials) and only falls back to interactive login if none is found.

ghlogin() {
    if ! command -v gh > /dev/null 2>&1; then
        echo -e "${RED}[ERROR]${NC} gh is not installed. Run ${GREEN}vps_update${NC} to install it."
        return 1
    fi

    if gh auth status > /dev/null 2>&1; then
        echo -e "${GREEN}[gh]${NC} Already authenticated."
        gh auth status 2>&1 | sed 's/^/  /'
        return 0
    fi

    # Find a token: $GH_TOKEN / $GITHUB_TOKEN first, else what git uses for github.com
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    local token_source="\$GH_TOKEN"

    if [ -z "$token" ] && [ -f "$HOME/.git-credentials" ]; then
        local line
        line=$(grep -m1 '@github\.com' "$HOME/.git-credentials" 2>/dev/null)
        if [ -n "$line" ]; then
            local userinfo="${line#*://}"   # user:token@github.com
            userinfo="${userinfo%@*}"        # user:token
            token="${userinfo##*:}"          # token (or whole field if no colon)
            token_source="~/.git-credentials"
        fi
    fi

    if [ -z "$token" ]; then
        echo -e "${YELLOW}[gh]${NC} No token found (checked \$GH_TOKEN and ~/.git-credentials)."
        echo -e "      Set GH_TOKEN, or log in interactively: ${GREEN}gh auth login${NC}"
        return 1
    fi

    if printf '%s' "$token" | gh auth login --hostname github.com --with-token 2>/dev/null; then
        echo -e "${GREEN}[gh]${NC} Authenticated using ${token_source}."
        return 0
    fi

    # 'gh auth login' requires the read:org scope. A token scoped only for git
    # push (such as the one in ~/.git-credentials) will not have it.
    echo -e "${YELLOW}[gh]${NC} The token from ${token_source} works for git but lacks"
    echo -e "      the 'read:org' scope that a stored 'gh' login requires. Either:"
    echo -e "        - create a PAT with 'repo' + 'read:org' and re-run ${GREEN}ghlogin${NC}, or"
    echo -e "        - export ${GREEN}GH_TOKEN${NC} — gh uses it directly, with no scope check."
    return 1
}
