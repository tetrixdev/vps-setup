#!/bin/bash
# Migration: Install the GitHub CLI (gh)
#
# Adds the official GitHub CLI apt repository and installs `gh`, so operators
# (and Claude Code) can manage pull requests, issues and releases from the
# server without hand-installing it.
#
# Idempotent: skips entirely if gh is already on PATH; the keyring and apt
# source are safe to (re)write.

migration_up() {
    if command -v gh > /dev/null 2>&1; then
        echo "GitHub CLI already installed ($(gh --version | head -1)), skipping"
        return 0
    fi

    local keyring="/usr/share/keyrings/githubcli-archive-keyring.gpg"
    local sources="/etc/apt/sources.list.d/github-cli.list"

    # Prerequisites for fetching the signing key over HTTPS
    if ! apt-get install -y -qq curl ca-certificates; then
        echo "Failed to install prerequisites (curl, ca-certificates)" >&2
        return 1
    fi

    # Official GitHub CLI signing key
    mkdir -p /usr/share/keyrings
    if ! curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$keyring"; then
        echo "Failed to download GitHub CLI signing key" >&2
        return 1
    fi
    chmod go+r "$keyring"

    # Official GitHub CLI apt repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" > "$sources"

    if ! apt-get update -qq; then
        echo "apt-get update failed after adding the GitHub CLI repository" >&2
        return 1
    fi
    if ! apt-get install -y -qq gh; then
        echo "Failed to install gh" >&2
        return 1
    fi

    echo "GitHub CLI installed ($(gh --version | head -1))"
}
