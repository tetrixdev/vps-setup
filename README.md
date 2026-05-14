# VPS Setup

Secures a fresh Ubuntu/Debian server for hosting web applications, and installs an operations toolkit for ongoing server management.

**Time required**: ~5 minutes

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash
```

You'll be prompted to choose an access restriction method:
1. **Tailscale (recommended)** - Zero-trust network access
2. **IP whitelist** - Restrict to specific IP addresses
3. **No restriction** - Public access (not recommended)

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Updates system, enables automatic security patches |
| 2 | Installs Docker with log rotation (50MB x 5 files per container) |
| 3 | Installs proxy-nginx reverse proxy (ports 80, 443) |
| 4 | Configures access restriction (Tailscale, IP whitelist, or none) |
| 5 | Hardens SSH (key-only auth, disables root login) |
| 6 | Creates `admin` user with sudo + docker access |
| 7 | Configures iptables firewall |
| 8 | Creates 4GB swap file |
| 9 | Installs VPS operations toolkit (update system, CLI helpers, migrations) |

---

## Operations Toolkit

After setup, the following commands are available on login:

### Server Management

| Command | Description |
|---------|-------------|
| `vps_update` | Pull latest updates and run new migrations |
| `vps_check` | Check if an update is available |

Updates are checked automatically on every SSH login.

### Container Helpers

Navigate to a project directory (e.g., `cd ~/docker-apps/myapp`) and use:

| Command | Description |
|---------|-------------|
| `bashphp` | Open shell in PHP container (as www-data) |
| `bashpostgres` | Open shell in PostgreSQL container |
| `bashnginx` | Open shell in nginx container |
| `bashredis` | Open shell in Redis container |
| `up` | Start the Docker Compose project |
| `down` | Graceful shutdown (Laravel-aware: maintenance mode, waits for jobs) |
| `syncvolume` | Interactive rsync of Docker volumes between servers |

All commands auto-detect the project by walking up the directory tree to find `compose.yml`.

### Migration System

Server configuration can be evolved incrementally via migrations:

```text
migrations/
├── 20260514_001_sysctl_tuning.sh
├── 20260514_002_expand_swap_4gb.sh
├── 20260514_003_refine_unattended_upgrades.sh
└── 20260514_004_prepare_heartbeat.sh
```

Migrations run automatically during `vps_update`. Each migration runs exactly once and is tracked in `/etc/vps-setup-migrations`. Failed migrations are retried on the next update.

### Heartbeat Monitoring

A heartbeat script runs every 15 minutes via cron, collecting server state (container statuses, OS info, update availability). By default it's inactive — configure `/etc/vps-setup-heartbeat.conf` with an endpoint URL to enable.

---

## Access Restriction Methods

| Method | SSH Access | Best For |
|--------|------------|----------|
| **Tailscale** | Via Tailscale only | Mobile/dynamic IPs, zero-trust |
| **IP Whitelist** | From specified IPs only | Static IPs, office networks |
| **No Restriction** | Public (port 22 open) | You handle security yourself |

### Tailscale (Recommended)

Zero-trust network access. SSH and PocketDev only accessible via your Tailscale network.

**Pros:**
- Works with dynamic IPs (mobile, home internet)
- SSH completely hidden from public internet
- Easy to add/remove access for team members

**Cons:**
- Requires Tailscale account (free tier available)

### IP Whitelist

Restrict access to specific IP addresses or CIDR ranges.

**Pros:**
- No additional service required
- Simple and predictable

**Cons:**
- Doesn't work well with dynamic IPs
- Need to update whitelist when IPs change

### No Restriction

PocketDev publicly accessible. **Not recommended.**

---

## Options

| Flag | Description |
|------|-------------|
| `--tailscale` | Use Tailscale (non-interactive) |
| `--ip-whitelist IPs` | Use IP whitelist (comma-separated IPs/CIDRs) |
| `--no-restriction` | No access restriction (not recommended) |
| `-h, --help` | Show help |

### Examples

```bash
# Interactive mode (prompts for choice)
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash

# Tailscale with auth key (for automation)
export TAILSCALE_KEY=tskey-xxx
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash -s -- --tailscale

# IP whitelist (non-interactive)
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash -s -- --ip-whitelist "1.2.3.4,10.0.0.0/8"

# No restriction (not recommended)
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash -s -- --no-restriction
```

---

## After Setup

### Connect

```bash
# Via Tailscale
ssh admin@<tailscale-ip>

# Via public IP (IP whitelist or no restriction mode)
ssh admin@<public-ip>
```

### Update Server

```bash
vps_update
```

This pulls the latest vps-setup code and runs any new migrations.

### Add Web Apps

Use the docker-apps directory convention:

```bash
cd ~/docker-apps
mkdir myapp && cd myapp
# Add compose.yml, .env, etc.

up        # Start the project
down      # Graceful shutdown
bashphp   # Shell into PHP container
```

proxy-nginx is pre-installed. Add domains with:

```bash
docker exec proxy-nginx /scripts/domain.sh upsert --domain=app.example.com --upstream=myapp-nginx
docker exec -it proxy-nginx certbot --nginx -d app.example.com
```

---

## Idempotency

The script is safe to re-run:

- **First run**: Access mode is determined by flags
- **Subsequent runs**: Uses stored mode from `/etc/vps-setup.conf`
- **Mode switching is blocked**: Cannot change between access modes
- **Migrations**: Track what has run, skip already-completed migrations

---

## What Gets Configured

### SSH Hardening

- Password authentication: **disabled**
- Root login: **disabled**
- Key authentication: **required**

Config stored at `/etc/ssh/sshd_config.d/00-vps-hardening.conf`.

### Firewall (iptables)

**Default (Tailscale):**
- SSH (port 22): Tailscale only
- HTTP (port 80): Public
- HTTPS (port 443): Public
- Tailscale interface: Allowed

**Docker containers:**
- Only reachable on whitelisted ports
- Accidental `docker run -p 3306:3306` won't expose your database

### Docker

- Log rotation: 50MB max x 5 files per container
- User added to `docker` group (no sudo needed)

### Automatic Updates

Security patches applied automatically via `unattended-upgrades`:
- Security origins (including ESM)
- Auto-reboot at 04:00 when required (kernel updates)
- Unused kernel packages cleaned up automatically

### Kernel Tuning

- `vm.swappiness=10` — Prefer keeping data in RAM
- `vm.dirty_ratio=15` — Limit dirty page cache before forcing sync writes
- `vm.dirty_background_ratio=5` — Start background flushing early

---

## Files Created/Modified

| Path | Purpose |
|------|---------|
| `/opt/vps-setup/` | VPS operations toolkit (this repo) |
| `/opt/proxy-nginx/` | proxy-nginx installation |
| `/etc/vps-setup.conf` | Setup configuration |
| `/etc/vps-setup-migrations` | Migration tracking |
| `/etc/vps-setup-heartbeat.conf` | Heartbeat endpoint configuration |
| `/var/log/vps-setup.log` | Operations log |
| `/etc/ssh/sshd_config.d/00-vps-hardening.conf` | SSH hardening |
| `/etc/sudoers.d/admin` | Passwordless sudo for admin user |
| `/etc/iptables/rules.v4` | Saved IPv4 firewall rules |
| `/etc/iptables/rules.v6` | Saved IPv6 firewall rules |
| `/etc/docker/daemon.json` | Docker log rotation config |
| `/etc/sysctl.d/99-vps-setup.conf` | Kernel parameter tuning |
| `/etc/apt/apt.conf.d/52unattended-upgrades-vps-setup` | Unattended-upgrades config |

---

## Troubleshooting

### Locked out of server

If you ran the script without an SSH key and got locked out:

1. Access via your provider's **web console** (VNC/Console)
2. Remove the hardening config:
   ```bash
   rm /etc/ssh/sshd_config.d/00-vps-hardening.conf
   systemctl restart ssh   # Ubuntu
   # or: systemctl restart sshd   # Debian
   ```
3. Add your SSH key properly, then re-run the script

### Docker permission denied

Log out and back in after running the script:

```bash
exit
ssh admin@<server-ip>
docker ps  # Should work now
```

### Can't connect via Tailscale

1. Check Tailscale is running on both devices: `tailscale status`
2. Ensure both are logged into the same Tailscale account
3. Check [Tailscale admin console](https://login.tailscale.com/admin/machines)

### proxy-nginx won't start

Check for config errors:

```bash
docker exec proxy-nginx nginx -t
```

View logs:

```bash
docker logs proxy-nginx
```

---

## Private Container Registries

If you're pulling images from private registries (like GitHub Container Registry), authenticate after setup:

### GitHub Container Registry (ghcr.io)

```bash
# Forward token via SSH (recommended)
ssh -o SendEnv=GITHUB_TOKEN admin@server \
  'echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin'

# Or manual login
echo "YOUR_TOKEN" | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

Credentials persist in `~/.docker/config.json`.

---

## Security Summary

| Layer | Protection |
|-------|------------|
| **SSH** | Key-only authentication, no root login |
| **Network** | SSH via Tailscale only (by default) |
| **Firewall** | Whitelist approach - only specified ports open |
| **Docker** | Containers only reachable on whitelisted ports |
| **Updates** | Automatic security patches with auto-reboot |
| **Kernel** | Tuned sysctl for I/O stability and memory management |

---

## License

MIT
