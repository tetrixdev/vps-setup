# VPS Setup

Secures a fresh Ubuntu/Debian server for hosting web applications or private development environments.

**Time required**: ~5 minutes

---

## Who This Is For

This script is for people who want to securely run Docker containers **without needing to understand iptables, SSH hardening, or Docker networking**.

If you just want to deploy containers safely and don't want to worry about accidentally exposing a database port to the internet — this is for you. The script makes opinionated choices so you don't have to.

**Not for you if:** You need custom firewall rules, non-standard port configurations, or want fine-grained control over every setting.

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Updates system, enables automatic security patches |
| 2 | Installs Docker with log rotation (50MB × 5 files per container) |
| 3 | Hardens SSH (key-only auth, disables root login) |
| 4 | Creates `admin` user with sudo + docker access |
| 5 | Configures iptables firewall (whitelist approach) |
| 6 | Creates 2GB swap file |

---

## Two Modes

| Mode | Command | Open Ports | Use Case |
|------|---------|------------|----------|
| **Public** | `--mode=public` | 22, 80, 443 + Tailscale | Web servers, public APIs |
| **Private** | `--mode=private` | Tailscale only | Dev environments, sensitive workloads |

Mode is **required** on first run. On subsequent runs, the script uses the stored mode automatically.

---

## Prerequisites

- Fresh **Ubuntu 24.04** or **Debian 12** server
- Your **SSH public key** added to the server
- For private mode: **Tailscale** installed and connected first

---

## Quick Start

### 1. Create Your VPS

| Setting | Recommended |
|---------|-------------|
| OS | Ubuntu 24.04 LTS |
| Specs | 2+ vCPU, 2+ GB RAM |
| SSH Key | **Add your public key** |
| Firewall | Skip (script configures iptables) |

### 2. SSH In and Run the Script

```bash
ssh root@<your-server-ip>
```

```bash
curl -O https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh
chmod +x setup.sh
./setup.sh --mode=public
```

### 3. Test the New User

**Before closing your root session**, open a new terminal and verify:

```bash
ssh admin@<your-server-ip>
```

If it works, you're done! Root login is now disabled.

---

## Private Mode (Tailscale-Only)

For servers that should be completely invisible to the public internet:

### 1. Install Tailscale First

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```

Follow the URL to authenticate. Note your Tailscale IP:

```bash
tailscale ip -4
# Example: 100.64.0.5
```

### 2. Run Setup in Private Mode

```bash
./setup.sh --mode=private
```

### 3. Connect via Tailscale

After setup, you can only reach the server through Tailscale:

```bash
ssh admin@<tailscale-ip>
```

The public IP will be completely unreachable.

---

## Usage

```text
./setup.sh --mode=<public|private>

Modes:
  --mode=public   Open ports 22, 80, 443 to the internet
  --mode=private  Tailscale-only access (all public ports blocked)
```

### Examples

```bash
# Public web server
./setup.sh --mode=public

# Private dev server
./setup.sh --mode=private

# Re-run (uses stored mode)
./setup.sh
```

### Mode Persistence

- First run: `--mode` is required
- Subsequent runs: Uses stored mode from `/etc/vps-setup-mode`
- Switching modes is blocked (could lock you out)

---

## What Gets Configured

### SSH Hardening

- Password authentication: **disabled**
- Root login: **disabled**
- Key authentication: **required**

Original config backed up to `/etc/ssh/sshd_config.backup`.

### Firewall (iptables)

**Both modes:**
- Tailscale interface always allowed (harmless if not installed)
- Loopback, established connections, ICMP allowed
- Everything else dropped

**Public mode additionally allows:**
- TCP 22 (SSH)
- TCP 80 (HTTP)
- TCP 443 (HTTPS)

**Docker containers:**
- Only reachable on whitelisted ports (80/443 in public mode, Tailscale in private)
- Accidental `docker run -p 3306:3306` won't expose your database

### Docker

- Log rotation: 50MB max × 5 files per container (250MB total)
- User added to `docker` group (no sudo needed)

### Automatic Updates

Security patches applied automatically via `unattended-upgrades`.

---

## Update Notifications

The script installs an update checker that runs on login. When a new version is available:

```text
[vps-setup] Update available: 1.0.0 → 1.1.0
  curl -O https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh && sudo bash setup.sh
```

The script is safe to re-run (note: Docker containers will restart).

---

## Adding SSH Keys

If your VPS provider doesn't support adding SSH keys during creation:

### On Your Local Machine

```bash
# View your public key
cat ~/.ssh/id_ed25519.pub

# Or generate one if you don't have it
ssh-keygen -t ed25519
```

### On the Server

```bash
mkdir -p ~/.ssh
echo 'YOUR_PUBLIC_KEY_HERE' >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Then run the setup script.

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

### Private mode: can't connect via Tailscale

1. Check Tailscale is running on both devices: `tailscale status`
2. Ensure both are logged into the same Tailscale account
3. Check [Tailscale admin console](https://login.tailscale.com/admin/machines)

### Script fails on non-Ubuntu/Debian

This script only supports Ubuntu and Debian. For other distributions, adapt the package installation commands.

---

## Security Summary

| Layer | Protection |
|-------|------------|
| **SSH** | Key-only authentication, no root login |
| **Firewall** | Whitelist approach — only specified ports open |
| **Docker** | Containers only reachable on whitelisted ports |
| **Updates** | Automatic security patches |

---

## Files Created/Modified

| Path | Purpose |
|------|---------|
| `/etc/vps-setup-version` | Installed version (for update checks) |
| `/etc/vps-setup-mode` | Stored mode (public/private) |
| `/etc/profile.d/vps-setup-update-check.sh` | Login update checker |
| `/etc/ssh/sshd_config.backup` | Original SSH config backup |
| `/etc/sudoers.d/admin` | Passwordless sudo for admin user |
| `/etc/iptables/rules.v4` | Saved IPv4 firewall rules |
| `/etc/iptables/rules.v6` | Saved IPv6 firewall rules |
| `/etc/docker/daemon.json` | Docker log rotation config |

---

## License

MIT
