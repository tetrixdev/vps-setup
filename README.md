# VPS Setup

Secures a fresh Ubuntu/Debian server with Tailscale for secure access.

**Time required**: ~5 minutes

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash
```

Follow the Tailscale authentication prompt. Once connected, SSH is only accessible via Tailscale.

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Updates system, enables automatic security patches |
| 2 | Installs Docker with log rotation (50MB x 5 files per container) |
| 3 | Installs proxy-nginx reverse proxy (ports 80, 443) |
| 4 | Installs and configures Tailscale |
| 5 | Hardens SSH (key-only auth, disables root login) |
| 6 | Creates `admin` user with sudo + docker access |
| 7 | Configures iptables firewall (SSH via Tailscale only) |
| 8 | Creates 2GB swap file |

---

## Architecture

```
Default Setup (Tailscale)              No-Tailscale Setup
========================               ==================
SSH: Tailscale only (port 22 blocked)  SSH: Public (port 22 open)
Web: Public (80/443 open)              Web: Public (80/443 open)
Tailscale: Required                    Tailscale: Not installed

Security: High                         Security: User's responsibility
```

---

## Options

| Flag | Description |
|------|-------------|
| `--no-tailscale` | Skip Tailscale, expose SSH publicly (advanced users) |
| `-y, --yes` | Non-interactive mode |
| `-h, --help` | Show help |

### Examples

```bash
# Default: Tailscale + proxy-nginx (recommended)
curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash

# With auth key (for automation)
TAILSCALE_KEY=tskey-xxx curl -fsSL .../setup.sh | bash

# Advanced: No Tailscale (user handles security themselves)
curl -fsSL .../setup.sh | bash -s -- --no-tailscale
```

---

## Automation

For automated setups (e.g., PocketDev deploying to new servers):

```bash
TAILSCALE_KEY=tskey-auth-xxx curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | bash
```

Generate an auth key at [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).

---

## After Setup

### Connect via Tailscale

```bash
ssh admin@<tailscale-ip>
```

Find your Tailscale IP:
```bash
tailscale ip -4
```

### Add Web Apps

proxy-nginx is pre-installed and ready for your web applications.

```bash
# Edit proxy-nginx config
nano /opt/proxy-nginx/default.conf

# Reload nginx after changes
docker exec proxy-nginx nginx -s reload

# Request SSL certificate
docker exec -it proxy-nginx certbot --nginx -d your-domain.com
```

### Example Nginx Config

Add this to `/opt/proxy-nginx/default.conf`:

```nginx
server {
    server_name www.example.com;

    client_max_body_size 256M;
    ssl_buffer_size 1400;  # SSE streaming optimization

    location / {
        set $upstream http://your-app-nginx;
        resolver 127.0.0.11 valid=30s;

        proxy_pass $upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # WebSocket/SSE support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }

    listen 80;
}
```

---

## Idempotency

The script is safe to re-run:

- **First run**: Tailscale mode is determined by flags
- **Subsequent runs**: Uses stored mode from `/etc/vps-setup.conf`
- **Mode switching is blocked**: Cannot change between Tailscale/no-Tailscale

If you need to switch modes, create a new server.

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

**With `--no-tailscale`:**
- SSH (port 22): Public
- HTTP (port 80): Public
- HTTPS (port 443): Public

**Docker containers:**
- Only reachable on whitelisted ports
- Accidental `docker run -p 3306:3306` won't expose your database

### Docker

- Log rotation: 50MB max x 5 files per container
- User added to `docker` group (no sudo needed)

### Automatic Updates

Security patches applied automatically via `unattended-upgrades`.

---

## Troubleshooting

### Locked out of server

If you ran the script without an SSH key and got locked out:

1. Access via your provider's **web console** (VNC/Console)
2. Remove the hardening config:
   ```bash
   rm /etc/ssh/sshd_config.d/00-vps-hardening.conf
   systemctl restart sshd
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

## Files Created/Modified

| Path | Purpose |
|------|---------|
| `/etc/vps-setup-version` | Installed version (for tracking) |
| `/etc/vps-setup.conf` | Configuration (Tailscale enabled/disabled) |
| `/etc/ssh/sshd_config.d/00-vps-hardening.conf` | SSH hardening |
| `/etc/sudoers.d/admin` | Passwordless sudo for admin user |
| `/etc/iptables/rules.v4` | Saved IPv4 firewall rules |
| `/etc/iptables/rules.v6` | Saved IPv6 firewall rules |
| `/etc/docker/daemon.json` | Docker log rotation config |
| `/opt/proxy-nginx/` | proxy-nginx installation |

---

## Security Summary

| Layer | Protection |
|-------|------------|
| **SSH** | Key-only authentication, no root login |
| **Network** | SSH via Tailscale only (by default) |
| **Firewall** | Whitelist approach - only specified ports open |
| **Docker** | Containers only reachable on whitelisted ports |
| **Updates** | Automatic security patches |

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

## License

MIT
