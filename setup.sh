#!/bin/bash
# =============================================================================
# VPS Setup Script
# =============================================================================
#
# Secures a fresh Ubuntu/Debian server with Tailscale for secure access.
#
# USAGE:
#   ./setup.sh                    # Default: Tailscale + proxy-nginx (recommended)
#   ./setup.sh --no-tailscale     # Advanced: Skip Tailscale (you handle SSH security)
#
# WHAT IT DOES:
#   1. Updates system and enables automatic security patches
#   2. Installs Docker with log rotation
#   3. Installs proxy-nginx reverse proxy
#   4. Installs and configures Tailscale (SSH via Tailscale only)
#   5. Hardens SSH (key-only auth, no root login)
#   6. Creates 'admin' user with sudo and docker access
#   7. Configures iptables firewall
#   8. Creates swap file (if none exists)
#
# PREREQUISITES:
#   - Fresh Ubuntu 24.04 or Debian 12 server
#   - SSH key already added (you'll be locked out without one!)
#
# ENVIRONMENT VARIABLES:
#   TAILSCALE_KEY    - Auth key for unattended Tailscale setup
#
# REPOSITORY: https://github.com/tetrixdev/vps-setup
#
# =============================================================================

set -euo pipefail  # Exit on error, undefined variable, or pipeline failure

SCRIPT_VERSION="2.0.0"
CONFIG_FILE="/etc/vps-setup.conf"
VERSION_FILE="/etc/vps-setup-version"
UPDATE_CHECK_SCRIPT="/etc/profile.d/vps-setup-update-check.sh"

# -----------------------------------------------------------------------------
# Colors and logging
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} ${1:-}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} ${1:-}"; }
log_error() { echo -e "${RED}[ERROR]${NC} ${1:-}"; }
log_step() { echo -e "\n${BLUE}==>${NC} ${1:-}"; }

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
SKIP_TAILSCALE=false
TAILSCALE_KEY="${TAILSCALE_KEY:-}"
USERNAME="admin"

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --no-tailscale    Skip Tailscale installation (advanced users only)"
    echo "  -y, --yes         Non-interactive mode (skip confirmations)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  TAILSCALE_KEY     Auth key for unattended Tailscale setup"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Default setup with Tailscale"
    echo "  TAILSCALE_KEY=tskey-xxx $0            # Unattended setup"
    echo "  $0 --no-tailscale                     # Skip Tailscale (not recommended)"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-tailscale)
            SKIP_TAILSCALE=true
            shift
            ;;
        -y|--yes)
            # Currently unused, but reserved for future non-interactive mode
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
log_step "Running pre-flight checks..."

# Must run as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root: sudo $0"
    exit 1
fi

# -----------------------------------------------------------------------------
# Check for mode mismatch (prevent switching between Tailscale/no-Tailscale)
# -----------------------------------------------------------------------------
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    STORED_TAILSCALE="${TAILSCALE_ENABLED:-}"

    if [ "$SKIP_TAILSCALE" = false ] && [ "$STORED_TAILSCALE" = "false" ]; then
        log_error "This server was set up WITHOUT Tailscale."
        log_error "Cannot add Tailscale to an existing no-Tailscale setup."
        echo ""
        echo "If you need Tailscale, create a new server and run setup without --no-tailscale."
        exit 1
    fi

    if [ "$SKIP_TAILSCALE" = true ] && [ "$STORED_TAILSCALE" = "true" ]; then
        log_error "This server was set up WITH Tailscale."
        log_error "Cannot switch to --no-tailscale mode."
        echo ""
        echo "If you need a no-Tailscale setup, create a new server."
        exit 1
    fi

    log_info "Re-running setup (mode unchanged)"
fi

# Detect distro
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_CODENAME="$VERSION_CODENAME"
else
    log_error "Cannot detect Linux distribution. /etc/os-release not found."
    exit 1
fi

if [ "$DISTRO_ID" != "ubuntu" ] && [ "$DISTRO_ID" != "debian" ]; then
    log_error "This script only supports Ubuntu and Debian. Detected: $DISTRO_ID"
    exit 1
fi

log_info "Detected: $DISTRO_ID $DISTRO_CODENAME"

# Check for SSH key before we lock out password auth
if [ ! -f /root/.ssh/authorized_keys ] || [ ! -s /root/.ssh/authorized_keys ]; then
    log_error "No SSH keys found in /root/.ssh/authorized_keys"
    log_error "Add your SSH key first, or you'll be locked out!"
    echo ""
    echo "To add your SSH key:"
    echo "  1. On your LOCAL machine, run: cat ~/.ssh/id_ed25519.pub"
    echo "  2. On this server, run:"
    echo "     mkdir -p ~/.ssh && echo 'YOUR_KEY_HERE' >> ~/.ssh/authorized_keys"
    exit 1
fi
log_info "SSH key found - safe to proceed"

# Show what will happen
echo ""
if [ "$SKIP_TAILSCALE" = true ]; then
    log_warn "NO-TAILSCALE MODE: SSH will be publicly accessible (port 22)"
    log_warn "You are responsible for SSH security!"
    echo ""
    echo "This script will:"
    echo "  1. Update system and enable automatic security updates"
    echo "  2. Install Docker with log rotation"
    echo "  3. Install proxy-nginx reverse proxy"
    echo "  4. Skip Tailscale (--no-tailscale)"
    echo "  5. Harden SSH (key-only, no root login)"
    echo "  6. Configure 'admin' user with sudo + docker access"
    echo "  7. Configure firewall (SSH, HTTP, HTTPS open)"
    echo "  8. Create 2GB swap file"
else
    log_info "SECURE MODE: SSH will only be accessible via Tailscale"
    echo ""
    echo "This script will:"
    echo "  1. Update system and enable automatic security updates"
    echo "  2. Install Docker with log rotation"
    echo "  3. Install proxy-nginx reverse proxy"
    echo "  4. Install and configure Tailscale"
    echo "  5. Harden SSH (key-only, no root login)"
    echo "  6. Configure 'admin' user with sudo + docker access"
    echo "  7. Configure firewall (SSH via Tailscale only, web public)"
    echo "  8. Create 2GB swap file"
fi
echo ""

# =============================================================================
# STEP 1: System Updates
# =============================================================================
log_step "Step 1/8: Updating system..."

export DEBIAN_FRONTEND=noninteractive

# Prevent interactive prompts from needrestart
if [ -d /etc/needrestart ]; then
    mkdir -p /etc/needrestart/conf.d
    echo '$nrconf{restart} = "a";' > /etc/needrestart/conf.d/no-prompt.conf
fi

apt-get update
apt-get upgrade -y

# Install essentials
apt-get install -y git nano curl wget gnupg ca-certificates jq

# Configure unattended-upgrades
log_info "Configuring automatic security updates..."
apt-get install -y unattended-upgrades

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

log_info "System updated, automatic security updates enabled"

# =============================================================================
# STEP 2: Install Docker
# =============================================================================
log_step "Step 2/8: Installing Docker..."

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    log_info "Docker already installed, skipping installation"
else
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$DISTRO_ID/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DISTRO_ID \
      $DISTRO_CODENAME stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Configure Docker daemon (log rotation: 50MB × 5 files = 250MB max per container)
log_info "Configuring Docker log rotation..."
mkdir -p /etc/docker

# Backup existing config if present
if [ -f /etc/docker/daemon.json ] && [ ! -f /etc/docker/daemon.json.backup ]; then
    cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
    log_info "Backed up existing Docker config to daemon.json.backup"
fi

cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file": "5"
    }
}
EOF

systemctl restart docker

# Verify Docker is running
if ! docker info >/dev/null 2>&1; then
    log_error "Docker failed to start. Check 'systemctl status docker' for details."
    exit 1
fi

log_info "Docker installed and configured"

# =============================================================================
# STEP 3: Install Proxy-Nginx
# =============================================================================
log_step "Step 3/8: Installing proxy-nginx..."

# Check if proxy-nginx already running
if docker ps --format '{{.Names}}' | grep -q '^proxy-nginx$'; then
    log_info "proxy-nginx already running"
else
    # Get latest version
    PROXY_VERSION=$(curl -sf "https://api.github.com/repos/tetrixdev/proxy-nginx/releases/latest" | jq -r '.tag_name' | sed 's/^v//')

    if [ -z "$PROXY_VERSION" ] || [ "$PROXY_VERSION" = "null" ]; then
        log_error "Could not fetch proxy-nginx version from GitHub"
        exit 1
    fi

    log_info "Installing proxy-nginx v${PROXY_VERSION}..."

    PROXY_DIR="/opt/proxy-nginx"
    mkdir -p "$PROXY_DIR"
    cd "$PROXY_DIR"

    # Download release
    curl -fsSL "https://github.com/tetrixdev/proxy-nginx/archive/refs/tags/v${PROXY_VERSION}.tar.gz" -o /tmp/proxy-nginx.tar.gz
    tar -xzf /tmp/proxy-nginx.tar.gz -C /tmp

    # Copy files
    cp "/tmp/proxy-nginx-${PROXY_VERSION}/compose/compose.yml" "$PROXY_DIR/"

    # Only copy default.conf if it doesn't exist (preserve user config)
    if [ ! -f "$PROXY_DIR/default.conf" ]; then
        cp "/tmp/proxy-nginx-${PROXY_VERSION}/compose/default.conf" "$PROXY_DIR/"
    fi

    # Update version in compose.yml
    sed -i "s/REPLACE_WITH_VERSION/$PROXY_VERSION/g" "$PROXY_DIR/compose.yml"

    # Create directories
    mkdir -p "$PROXY_DIR/letsencrypt"

    # Cleanup
    rm -rf /tmp/proxy-nginx.tar.gz /tmp/proxy-nginx-*

    # Start proxy-nginx
    docker compose pull
    docker compose up -d

    log_info "proxy-nginx v${PROXY_VERSION} installed"
fi

# =============================================================================
# STEP 4: Install Tailscale
# =============================================================================
TAILSCALE_IP=""

if [ "$SKIP_TAILSCALE" = false ]; then
    log_step "Step 4/8: Installing Tailscale..."

    # Install if not present
    if ! command -v tailscale &> /dev/null; then
        log_info "Installing Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        log_info "Tailscale already installed"
    fi

    # Check if already authenticated
    if tailscale status &> /dev/null; then
        TAILSCALE_IP=$(tailscale ip -4)
        log_info "Tailscale already connected: $TAILSCALE_IP"
    else
        # Need to authenticate
        if [ -n "$TAILSCALE_KEY" ]; then
            log_info "Authenticating with provided auth key..."
            tailscale up --auth-key="$TAILSCALE_KEY" --ssh
        else
            log_info "Please authenticate Tailscale (follow the URL):"
            tailscale up --ssh
        fi

        # Wait a moment for connection
        sleep 2

        # Verify connection
        if tailscale status &> /dev/null; then
            TAILSCALE_IP=$(tailscale ip -4)
            log_info "Tailscale connected: $TAILSCALE_IP"
        else
            log_error "Tailscale authentication failed"
            log_error "Run 'tailscale up --ssh' manually to authenticate"
            exit 1
        fi
    fi
else
    log_step "Step 4/8: Skipping Tailscale (--no-tailscale)"
    log_warn "SSH will be publicly accessible. You are responsible for security."
fi

# =============================================================================
# STEP 5: SSH Hardening
# =============================================================================
log_step "Step 5/8: Hardening SSH..."

# Backup original config (only once)
if [ ! -f /etc/ssh/sshd_config.backup ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
fi

# Use drop-in config for reliability (survives cloud-init, package updates)
# Named 00-* to load FIRST - OpenSSH uses first-match-wins with alphabetical order
log_info "Creating SSH hardening drop-in config..."
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/00-vps-hardening.conf << 'EOF'
# VPS Setup SSH Hardening
# Named 00-* to load first and take precedence (OpenSSH first-match-wins)

PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
PermitEmptyPasswords no

# Allow forwarding environment variables (for tokens, etc.)
# Client must explicitly send with: ssh -o SendEnv=VAR_NAME
AcceptEnv *
EOF

# Verify sshd config is valid before restarting
if ! sshd -t 2>/dev/null; then
    log_error "SSH config validation failed. Restoring backup..."
    rm -f /etc/ssh/sshd_config.d/00-vps-hardening.conf
    exit 1
fi

# Restart SSH (existing sessions stay alive)
# Ubuntu uses 'ssh' service, Debian uses 'sshd'
if systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl restart ssh
elif systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl restart sshd
else
    log_warn "Could not determine SSH service name, skipping restart"
fi

log_info "SSH hardened: password auth disabled, root login disabled"

# =============================================================================
# STEP 6: Configure User
# =============================================================================
log_step "Step 6/8: Configuring user '$USERNAME'..."

if id "$USERNAME" &>/dev/null; then
    log_info "User '$USERNAME' already exists"
else
    useradd -m -s /bin/bash "$USERNAME"
    log_info "Created user '$USERNAME'"
fi

# Add to sudo group
usermod -aG sudo "$USERNAME"

# Add to docker group
usermod -aG docker "$USERNAME"

# Copy SSH keys from root (if user doesn't have them yet)
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
mkdir -p "$USER_HOME/.ssh"

if [ ! -f "$USER_HOME/.ssh/authorized_keys" ] || [ ! -s "$USER_HOME/.ssh/authorized_keys" ]; then
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/authorized_keys"
    log_info "Copied SSH keys to $USERNAME"
else
    log_info "User already has SSH keys"
fi

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

# Allow sudo without password
# This is intentional for automation/deployment scripts. The security model is:
# - SSH key required for access (no password auth)
# - Once authenticated via SSH key, sudo is allowed
# - If SSH key is compromised, attacker has access anyway
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"

log_info "User '$USERNAME' configured with sudo + docker access"

# =============================================================================
# STEP 7: Configure Firewall (iptables)
# =============================================================================
log_step "Step 7/8: Configuring firewall..."

# Install iptables-persistent (non-interactive)
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get install -y iptables-persistent

# -----------------------------------------------------------------------------
# Helper: add iptables rule if it doesn't exist (idempotent)
# -----------------------------------------------------------------------------
ipt_add() {
    iptables -C "$@" 2>/dev/null || iptables -A "$@"
}
ipt6_add() {
    ip6tables -C "$@" 2>/dev/null || ip6tables -A "$@"
}

# -----------------------------------------------------------------------------
# IPv4 INPUT chain (host protection)
# -----------------------------------------------------------------------------
log_info "Configuring IPv4 firewall rules..."

# Set policies (DROP policies set AFTER rules to avoid lockout on failure)
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

# Allow loopback
ipt_add INPUT -i lo -j ACCEPT

# Allow established connections
ipt_add INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP (ping)
ipt_add INPUT -p icmp -j ACCEPT

# Always allow Tailscale interface and UDP port
ipt_add INPUT -i tailscale0 -j ACCEPT
ipt_add INPUT -p udp --dport 41641 -j ACCEPT

# Web traffic always allowed (proxy-nginx handles it)
ipt_add INPUT -p tcp --dport 80 -j ACCEPT
ipt_add INPUT -p tcp --dport 443 -j ACCEPT

if [ "$SKIP_TAILSCALE" = true ]; then
    # No-Tailscale mode: also allow public SSH
    log_warn "Opening SSH (port 22) to public (--no-tailscale mode)"
    ipt_add INPUT -p tcp --dport 22 -j ACCEPT
else
    # Default: SSH only via Tailscale (no public SSH rule)
    log_info "SSH accessible only via Tailscale (port 22 blocked from public)"
fi

# Now set INPUT policy to DROP (after rules are in place)
iptables -P INPUT DROP

# -----------------------------------------------------------------------------
# DOCKER-USER chain (container access control)
# -----------------------------------------------------------------------------
log_info "Configuring Docker firewall rules..."

# Create DOCKER-USER chain if it doesn't exist
iptables -N DOCKER-USER 2>/dev/null || true

# Allow established connections (responses to outbound requests)
ipt_add DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# Allow Docker internal traffic (container-to-container)
ipt_add DOCKER-USER -i docker0 -o docker0 -j RETURN
ipt_add DOCKER-USER -i br-+ -o br-+ -j RETURN

# Allow container outbound traffic (container -> internet)
ipt_add DOCKER-USER -s 172.16.0.0/12 ! -d 172.16.0.0/12 -j RETURN

# Always allow Tailscale to reach containers
ipt_add DOCKER-USER -i tailscale0 -j RETURN

# Allow web traffic to reach containers (ports 80, 443)
ipt_add DOCKER-USER -p tcp -m conntrack --ctorigdstport 80 -j RETURN
ipt_add DOCKER-USER -p tcp -m conntrack --ctorigdstport 443 -j RETURN

# Block everything else to containers (must be last)
# This prevents accidental exposure (e.g., docker run -p 3306:3306 won't work)
ipt_add DOCKER-USER -j DROP

# -----------------------------------------------------------------------------
# IPv6 Rules
# -----------------------------------------------------------------------------
log_info "Configuring IPv6 firewall rules..."

# Set policies (DROP policies set AFTER rules to avoid lockout on failure)
ip6tables -P OUTPUT ACCEPT
ip6tables -P FORWARD DROP

# IPv6 INPUT chain
ipt6_add INPUT -i lo -j ACCEPT
ipt6_add INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ipt6_add INPUT -p ipv6-icmp -j ACCEPT
ipt6_add INPUT -i tailscale0 -j ACCEPT

# Web traffic always allowed
ipt6_add INPUT -p tcp --dport 80 -j ACCEPT
ipt6_add INPUT -p tcp --dport 443 -j ACCEPT

if [ "$SKIP_TAILSCALE" = true ]; then
    # No-Tailscale mode: also allow public SSH over IPv6
    ipt6_add INPUT -p tcp --dport 22 -j ACCEPT
fi

# Now set INPUT policy to DROP (after rules are in place)
ip6tables -P INPUT DROP

# IPv6 DOCKER-USER chain (container access control)
ip6tables -N DOCKER-USER 2>/dev/null || true
ipt6_add DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
ipt6_add DOCKER-USER -i docker0 -o docker0 -j RETURN
ipt6_add DOCKER-USER -i br-+ -o br-+ -j RETURN
ipt6_add DOCKER-USER -i tailscale0 -j RETURN
ipt6_add DOCKER-USER -p tcp -m conntrack --ctorigdstport 80 -j RETURN
ipt6_add DOCKER-USER -p tcp -m conntrack --ctorigdstport 443 -j RETURN
ipt6_add DOCKER-USER -j DROP

# -----------------------------------------------------------------------------
# Save iptables rules
# -----------------------------------------------------------------------------
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

if [ "$SKIP_TAILSCALE" = true ]; then
    log_info "Firewall configured: SSH (22), HTTP (80), HTTPS (443)"
else
    log_info "Firewall configured: HTTP (80), HTTPS (443) + Tailscale (SSH via Tailscale only)"
fi

# =============================================================================
# STEP 8: Create Swap File
# =============================================================================
log_step "Step 8/8: Configuring swap..."

if [ -f /swapfile ] || [ "$(swapon --show | wc -l)" -gt 0 ]; then
    log_info "Swap already exists, skipping"
else
    # Create swap file (fallocate is faster, dd is fallback for unsupported filesystems)
    if ! fallocate -l 2G /swapfile 2>/dev/null; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
    fi
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Make permanent (idempotent)
    grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Optimize swappiness (idempotent)
    grep -qxF 'vm.swappiness=10' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
    sysctl vm.swappiness=10

    log_info "2GB swap file created"
fi

# =============================================================================
# Save configuration
# =============================================================================
log_info "Saving configuration..."

cat > "$CONFIG_FILE" << EOF
# VPS Setup Configuration
# Generated: $(date -Iseconds)
# Do not edit manually - this file is used to detect setup mode

TAILSCALE_ENABLED=$([ "$SKIP_TAILSCALE" = false ] && echo "true" || echo "false")
VERSION="$SCRIPT_VERSION"
INSTALLED_AT="$(date -Iseconds)"
EOF

echo "$SCRIPT_VERSION" > "$VERSION_FILE"

# Create update check script (runs on login)
cat > "$UPDATE_CHECK_SCRIPT" << 'UPDATEEOF'
#!/bin/bash
# Check for vps-setup updates on login (once per day)

VERSION_FILE="/etc/vps-setup-version"
REPO_API="https://api.github.com/repos/tetrixdev/vps-setup/releases/latest"
CHECK_FILE="/tmp/.vps-setup-check-$(id -u)"

# Only check once per day per user
if [ -f "$CHECK_FILE" ]; then
    LAST_CHECK=$(stat -c %Y "$CHECK_FILE" 2>/dev/null || stat -f %m "$CHECK_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ $((NOW - LAST_CHECK)) -lt 86400 ]; then
        return 0 2>/dev/null || exit 0
    fi
fi

if [ -f "$VERSION_FILE" ]; then
    LOCAL_VERSION=$(cat "$VERSION_FILE")
    REMOTE_VERSION=$(curl -sf "$REPO_API" 2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"v\?\([^"]*\)".*/\1/')

    # Only update throttle file if curl succeeded (REMOTE_VERSION is set)
    if [ -n "$REMOTE_VERSION" ]; then
        touch "$CHECK_FILE" 2>/dev/null

        if [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
            echo ""
            echo -e "\033[1;33m[vps-setup]\033[0m Update available: $LOCAL_VERSION → $REMOTE_VERSION"
            echo "  curl -fsSL https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh | sudo bash"
            echo ""
        fi
    fi
fi
UPDATEEOF

chmod +x "$UPDATE_CHECK_SCRIPT"

# =============================================================================
# Complete
# =============================================================================
echo ""
echo "============================================================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "============================================================================="
echo ""
echo "Installed:"
echo "  ✓ Automatic security updates"
echo "  ✓ Docker with log rotation (50MB × 5 files per container)"
echo "  ✓ proxy-nginx reverse proxy (ports 80, 443)"
if [ "$SKIP_TAILSCALE" = false ]; then
    echo "  ✓ Tailscale (SSH via Tailscale only)"
else
    echo "  ✗ Tailscale (skipped - SSH publicly accessible)"
fi
echo "  ✓ SSH: key-only, no root login"
echo "  ✓ User 'admin' with sudo + docker"
echo "  ✓ Firewall configured"
echo "  ✓ 2GB swap file"
echo ""
if [ "$SKIP_TAILSCALE" = false ]; then
    echo "Connect via Tailscale:"
    echo "  ssh $USERNAME@$TAILSCALE_IP"
    echo ""
    log_info "SSH is only accessible via Tailscale. Public SSH is blocked."
else
    echo "Connect via:"
    echo "  ssh $USERNAME@<public-ip>"
    echo ""
    log_warn "SSH is publicly accessible (port 22). Consider using Tailscale."
fi
echo ""
echo "Add web apps:"
echo "  1. Edit: nano /opt/proxy-nginx/default.conf"
echo "  2. Reload: docker exec proxy-nginx nginx -s reload"
echo "  3. SSL: docker exec -it proxy-nginx certbot --nginx -d your-domain.com"
echo ""
echo "============================================================================="
echo ""
log_warn "IMPORTANT: Root login is now disabled."
log_warn "Test the new user login BEFORE closing this session!"
echo ""
if [ "$SKIP_TAILSCALE" = false ]; then
    echo "In a NEW terminal, run:"
    echo "  ssh $USERNAME@$TAILSCALE_IP"
else
    echo "In a NEW terminal, run:"
    echo "  ssh $USERNAME@<public-ip>"
fi
echo ""
