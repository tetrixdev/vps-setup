# VPS Setup

Secures a fresh Ubuntu/Debian server for hosting web applications or private development environments.

**Time required**: ~5 minutes

---

## What It Does

| Step | Action |
|------|--------|
| 1 | Updates system, enables automatic security patches |
| 2 | Installs Docker with log rotation |
| 3 | Hardens SSH (key-only auth, disables root login) |
| 4 | Creates non-root user with sudo + docker access |
| 5 | Configures iptables firewall |
| 6 | Creates 2GB swap file |

---

## Two Modes

| Mode | Command | Open Ports | Use Case |
|------|---------|------------|----------|
| **Public** | `./setup.sh` | 22, 80, 443 | Web servers, public APIs |
| **Private** | `./setup.sh --private` | None (Tailscale only) | Dev environments, sensitive workloads |

---

## Prerequisites

- Fresh **Ubuntu 24.04** or **Debian 12** server
- Your **SSH public key** added to the server

Most VPS providers let you add SSH keys during server creation. If not, see [Adding SSH Keys](#adding-ssh-keys) below.

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
./setup.sh
```

### 3. Test the New User

**Before closing your root session**, open a new terminal and verify:

```bash
ssh deploy@<your-server-ip>
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
./setup.sh --private
```

### 3. Connect via Tailscale

After setup, you can only reach the server through Tailscale:

```bash
ssh deploy@<tailscale-ip>
```

The public IP will be completely unreachable.

---

## Options

```
./setup.sh [OPTIONS]

Options:
  --private       Tailscale-only mode (no public ports)
  --username=X    Username to create (default: deploy)
  --skip-user     Don't create a new user
  -y, --yes       Skip confirmation prompt (for automation)
  -h, --help      Show help
```

### Examples

```bash
# Standard public web server
./setup.sh

# Private server with Tailscale
./setup.sh --private

# Custom username
./setup.sh --username=myuser

# Skip user creation (already have a non-root user)
./setup.sh --skip-user
```

---

## What Gets Configured

### SSH Hardening

- Password authentication: **disabled**
- Root login: **disabled**
- Key authentication: **required**

Original config backed up to `/etc/ssh/sshd_config.backup`.

### Firewall (iptables)

**Public mode:**
- Inbound: 22 (SSH), 80 (HTTP), 443 (HTTPS)
- Docker containers: only reachable on 80/443
- Everything else: dropped

**Private mode:**
- Inbound: only Tailscale interface
- Docker containers: only reachable via Tailscale
- Public IP: completely blocked

### Docker

- Log rotation: 10MB max, 3 files per container
- User added to `docker` group (no sudo needed)

### Automatic Updates

Security patches applied automatically via `unattended-upgrades`.

---

## Update Notifications

The script installs an update checker that runs on login. When a new version is available, you'll see:

```
[vps-setup] Update available: 1.0.0 → 1.1.0
  curl -O https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh && sudo bash setup.sh
```

The script is idempotent — safe to re-run.

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
2. Edit `/etc/ssh/sshd_config`:
   ```bash
   nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication yes
   # Set: PermitRootLogin yes
   ```
3. Restart SSH: `systemctl restart sshd`
4. Add your SSH key properly, then re-run the script

### Docker permission denied

Log out and back in after running the script:

```bash
exit
ssh deploy@<server-ip>
docker ps  # Should work now
```

### Private mode: can't connect via Tailscale

1. Check Tailscale is running on both devices: `tailscale status`
2. Ensure both are logged into the same Tailscale account
3. Check [Tailscale admin console](https://login.tailscale.com/admin/machines)

### Script fails on non-Ubuntu/Debian

This script only supports Ubuntu and Debian. For other distributions, you'll need to adapt the package installation commands.

---

## Security Summary

| Layer | Protection |
|-------|------------|
| **SSH** | Key-only authentication, no root login |
| **Firewall** | Whitelist approach — only specified ports open |
| **Docker** | Containers only reachable on whitelisted ports |
| **Updates** | Automatic security patches |

---

## Files Created

| Path | Purpose |
|------|---------|
| `/etc/vps-setup-version` | Installed version (for update checks) |
| `/etc/profile.d/vps-setup-update-check.sh` | Login update checker |
| `/etc/ssh/sshd_config.backup` | Original SSH config backup |
| `/etc/sudoers.d/<username>` | Passwordless sudo for created user |
| `/etc/iptables/rules.v4` | Saved IPv4 firewall rules |
| `/etc/iptables/rules.v6` | Saved IPv6 firewall rules |

---

## License

MIT
