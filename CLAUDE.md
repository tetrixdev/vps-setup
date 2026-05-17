# VPS Setup

Server provisioning and operations toolkit for Ubuntu/Debian servers running Docker-based web applications.

## Repository Structure

```text
vps-setup/
├── setup.sh                 # Initial server provisioning (run once via curl)
├── scripts/
│   ├── bootstrap.sh         # Sourced on login via .bashrc (loads all functions)
│   ├── internal.sh          # Core: vps_update, vps_check, migrations, claude-context sync
│   └── heartbeat.sh         # Server health reporting (cron, every 15 min)
├── functions/               # User-facing shell commands
│   ├── bashphp.sh           # Open shell in PHP container
│   ├── bashpostgres.sh      # Open shell in PostgreSQL container
│   ├── bashnginx.sh         # Open shell in nginx container
│   ├── bashredis.sh         # Open shell in Redis container
│   ├── up.sh                # Start a Docker Compose project
│   ├── down.sh              # Graceful shutdown (Laravel-aware)
│   ├── syncvolume.sh        # Rsync Docker volumes between servers
│   └── ghsetup.sh           # Configure GitHub integration (git, gh, ghcr.io)
├── templates/               # Files rendered onto servers
│   └── claude-context.md    # Managed block of the admin user's CLAUDE.md
└── migrations/              # Incremental server config changes
    ├── YYYYMMDD_NNN_*.sh    # Timestamped, idempotent migration scripts
    └── .gitkeep
```

## Key Paths on Server

| Path | Purpose |
|------|---------|
| `/opt/vps-setup/` | This repo (cloned during setup) |
| `/opt/proxy-nginx/` | Reverse proxy installation |
| `/etc/vps-setup.conf` | Setup config (access mode, install date) |
| `/etc/vps-setup-migrations` | Migration tracker (which migrations have run) |
| `/etc/vps-setup-heartbeat.conf` | Heartbeat endpoint config |
| `/var/log/vps-setup.log` | Centralized operations log |
| `~/docker-apps/` | Convention: Docker Compose projects live here |

## Migration System

Migrations enable incremental server configuration changes. Push a new migration
to the repo, operators run `vps_update`, and it applies automatically.

### Creating a Migration

1. Create a file in `migrations/` with naming: `YYYYMMDD_NNN_description.sh`
2. Define a `migration_up()` function
3. The function MUST be idempotent (safe to run if the desired state already exists)

```bash
#!/bin/bash
# Migration: Brief description of what this does

migration_up() {
    # Check if already done
    if [ -f /etc/myconfig ]; then
        echo "Already configured, skipping"
        return 0
    fi

    # Do the thing
    echo "configvalue" > /etc/myconfig
    echo "Configuration applied"
}
```

### Critical Rules

- **Idempotent**: Check state before acting. If the desired state already exists, return 0.
- **Atomic**: If a migration fails partway, it must be safe to re-run.
- **No user input**: Migrations run non-interactively (during install and updates).
- **Sudo access**: Migrations run as root. Use `apt-get -y -qq` for package installs.
- **Order matters**: Migrations run in filename order. A migration can depend on earlier ones.
- **Failure stops the chain**: If a migration fails, subsequent ones don't run. The failed migration will be retried on next `vps_update`.
- **Never delete a migration**: Old migrations must stay in the repo. New servers run all of them from the beginning.

### How It Works

1. `vps_run_migrations()` scans `migrations/*.sh` sorted by filename
2. Compares against `/etc/vps-setup-migrations` (records: `filename|timestamp`)
3. For each unrecorded migration: sources it, calls `migration_up()`
4. On success: records it. On failure: stops (will retry next time).

## Update System

- `vps_check`: Fetches origin/main, shows if update available
- `vps_update`: `git pull` + `vps_run_migrations()` + `_vps_sync_claude_context()` (auto-escalates to sudo)
- On login: `vps_check --quiet` runs automatically (only shows message if update available)

## Claude Context File

`templates/claude-context.md` is rendered into the admin user's `~/CLAUDE.md` so
any Claude Code session on the server starts with the ops cheatsheet.

`_vps_sync_claude_context()` (internal.sh) writes the template between
`<!-- vps-setup:managed:start -->` / `<!-- vps-setup:managed:end -->` markers and
runs on every `vps_update`. Only the managed block is replaced — anything below
the end marker is operator-owned and never touched. Migration
`20260517_001_deploy_claude_md.sh` performs the initial rollout by calling the
same function once.

To change what servers receive, edit `templates/claude-context.md` — the next
`vps_update` picks it up. Do not add a new migration for content changes.

## GitHub Integration

A single GitHub token authenticates three things — git push over HTTPS, the
`gh` CLI, and docker pulls from ghcr.io. `functions/ghsetup.sh` (the `ghsetup`
command) configures all three, plus the git author identity, for the current
user.

- `setup.sh` accepts `--github-token` / `--git-name` / `--git-email` (or the
  `GITHUB_TOKEN` env var), prompts for them interactively, and runs `ghsetup`
  as the admin user after migrations (so `gh` is already installed).
- `migrations/20260517_002_install_gh.sh` installs `gh` itself.
- `_vps_github_nag()` (internal.sh, called from bootstrap.sh) reminds on
  interactive login if any of the three is unconfigured. It only reports
  current state — it is not tied to setup. Silenced once configured, or with
  `touch ~/.vps-setup-no-github-nag`.

The token needs the `repo`, `read:packages` and `read:org` scopes.

## Swap Policy

4GB swap is standard regardless of server RAM size.

- Swap is a safety buffer for transient memory spikes, not a performance feature.
- If the server regularly uses swap, the fix is upgrading RAM, not adding more swap.
- Smaller swap risks OOM-killing containers under brief spikes.
- Larger swap delays OOM alerts and masks real memory pressure.

## Container Helper Functions

All container commands auto-detect the current project by walking up the directory
tree to find `compose.yml` and extracting the container prefix from `container_name`.

Convention: navigate to a project directory (e.g., `cd ~/docker-apps/myapp`) and
commands like `bashphp`, `up`, `down` work automatically.

## Heartbeat

Prepared but inactive by default. Configure `/etc/vps-setup-heartbeat.conf` with
a monitoring endpoint URL and token to enable. Sends server state JSON every 15 min.
Set `HEARTBEAT_ENABLED=false` to suppress the login nag without configuring a URL.

## Installation Path (`/opt/vps-setup`)

The installation path is hardcoded in four files. If this ever changes, update all:
- `scripts/bootstrap.sh` (line 10: `VPS_SETUP_DIR=`)
- `scripts/internal.sh` (line 14: `VPS_SETUP_DIR=`)
- `scripts/heartbeat.sh` (line 17: `VPS_SETUP_DIR=`)
- `migrations/20260514_004_prepare_heartbeat.sh` (line 10: `local VPS_SETUP_DIR=`)

## Design Decisions

Documented here so future reviewers understand intentional tradeoffs:

- **StrictHostKeyChecking=accept-new in syncvolume**: Trusts on first connect, verifies
  subsequent (TOFU). Strict mode would require pre-distributing host keys, impractical
  for an interactive one-off migration tool.
- **Heartbeat cron runs as root**: Needs docker access and git access to /opt/vps-setup.
  Admin has NOPASSWD:ALL sudo, so root adds no blast radius.
- **No checksum verification for downloads**: HTTPS is sufficient for a personal VPS
  toolkit. Maintaining checksums for every upstream release adds ongoing burden.
- **vps_update pulls HEAD of main**: Standard usage always matches. Pinned-commit edge
  cases are not worth the complexity of version-matching logic.
- **SSHPASS via env var**: Only root can read /proc/pid/environ for root processes.
  Admin already has root via NOPASSWD sudo. Acceptable for an interactive admin tool.
- **Background vps_check may print mid-typing**: Alternatives (PROMPT_COMMAND, temp file)
  add complexity for a minor annoyance. No data is lost.
- **Proxy-nginx guard duplicated in bash\* files**: Each handler has intentionally
  different behavior (bashnginx opens a shell, others error). Centralizing would
  over-abstract a simple string comparison.
