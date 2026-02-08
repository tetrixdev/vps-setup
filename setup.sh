#!/bin/bash
# =============================================================================
# VPS Setup Script
# =============================================================================
#
# Secures a fresh Ubuntu/Debian server for hosting web applications or
# private development environments.
#
# USAGE:
#   ./setup.sh --mode=public              Public web server (ports 22, 80, 443)
#   ./setup.sh --mode=private             Private server (Tailscale-only)
#   ./setup.sh --mode=public --username=X Specify username to create
#
# WHAT IT DOES:
#   1. Updates system and enables automatic security patches
#   2. Installs Docker with log rotation
#   3. Hardens SSH (key-only auth, no root login)
#   4. Creates/configures a non-root user with sudo and docker access
#   5. Configures iptables firewall
#   6. Creates swap file (if none exists)
#
# PREREQUISITES:
#   - Fresh Ubuntu 24.04 or Debian 12 server
#   - SSH key already added (you'll be locked out without one!)
#   - For --mode=private: Tailscale installed and connected first
#
# REPOSITORY: https://github.com/tetrixdev/vps-setup
#
# =============================================================================

set -e  # Exit on any error

SCRIPT_VERSION="1.0.0"
VERSION_FILE="/etc/vps-setup-version"
MODE_FILE="/etc/vps-setup-mode"
UPDATE_CHECK_SCRIPT="/etc/profile.d/vps-setup-update-check.sh"

# -----------------------------------------------------------------------------
# Colors and logging
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}==>${NC} $1"; }

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
MODE=""
USERNAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=public)
            MODE="public"
            shift
            ;;
        --mode=private)
            MODE="private"
            shift
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --username=*)
            USERNAME="${1#*=}"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --mode=<public|private> [OPTIONS]"
            echo ""
            echo "Required:"
            echo "  --mode=public   Open ports 22, 80, 443 to the internet"
            echo "  --mode=private  Tailscale-only access (all public ports blocked)"
            echo ""
            echo "Options:"
            echo "  --username=X    Username to create (auto-detects existing user if not provided)"
            echo "  -h, --help      Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --mode=public                    # Public web server"
            echo "  $0 --mode=private                   # Private dev server"
            echo "  $0 --mode=public --username=deploy  # Public with specific user"
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
    log_error "Please run as root: sudo $0 --mode=<public|private>"
    exit 1
fi

# -----------------------------------------------------------------------------
# Mode handling: require mode on first run, enforce consistency on re-run
# -----------------------------------------------------------------------------
if [ -f "$MODE_FILE" ]; then
    STORED_MODE=$(cat "$MODE_FILE")

    if [ -z "$MODE" ]; then
        # Re-run without --mode: use stored mode
        MODE="$STORED_MODE"
        log_info "Using previously configured mode: $MODE"
    elif [ "$MODE" != "$STORED_MODE" ]; then
        # Trying to switch modes: not allowed
        log_error "Cannot switch modes. This server is configured as '$STORED_MODE'."
        log_error "Switching from $STORED_MODE to $MODE could lock you out."
        echo ""
        echo "If you really need to switch modes, manually remove $MODE_FILE first."
        exit 1
    fi
else
    # First run: mode is required
    if [ -z "$MODE" ]; then
        log_error "Mode is required on first run."
        echo ""
        echo "Usage: $0 --mode=<public|private>"
        echo ""
        echo "  --mode=public   For web servers (opens ports 22, 80, 443)"
        echo "  --mode=private  For dev environments (Tailscale-only access)"
        exit 1
    fi
fi

# Validate mode value
if [ "$MODE" != "public" ] && [ "$MODE" != "private" ]; then
    log_error "Invalid mode: $MODE"
    echo "Mode must be 'public' or 'private'"
    exit 1
fi

# Detect distro
if [ -f /etc/os-release ]; then
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
log_info "Mode: $MODE"

# -----------------------------------------------------------------------------
# User detection: find existing user or require --username
# -----------------------------------------------------------------------------
# Find existing non-root users (UID >= 1000, real shell, not nobody)
detect_existing_user() {
    getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 && $7 !~ /nologin|false/ {print $1}' | head -1
}

EXISTING_USER=$(detect_existing_user)

if [ -n "$USERNAME" ]; then
    # Username explicitly provided
    log_info "Using specified username: $USERNAME"
elif [ -n "$EXISTING_USER" ]; then
    # Found existing user
    USERNAME="$EXISTING_USER"
    log_info "Detected existing user: $USERNAME"
else
    # No user provided and none exists
    log_error "No existing non-root user found and --username not provided."
    echo ""
    echo "Specify a username to create:"
    echo "  $0 --mode=$MODE --username=deploy"
    exit 1
fi

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

# Private mode requires Tailscale
if [ "$MODE" = "private" ]; then
    if ! command -v tailscale &> /dev/null; then
        log_error "Private mode requires Tailscale. Install it first:"
        echo "  curl -fsSL https://tailscale.com/install.sh | sh"
        echo "  sudo tailscale up --ssh"
        exit 1
    fi

    if ! tailscale status &> /dev/null; then
        log_error "Tailscale is installed but not connected."
        echo "  Run: sudo tailscale up --ssh"
        exit 1
    fi

    TAILSCALE_IP=$(tailscale ip -4)
    log_info "Tailscale connected: $TAILSCALE_IP"
fi

# Show what will happen
echo ""
if [ "$MODE" = "private" ]; then
    log_warn "PRIVATE MODE: Server will only be accessible via Tailscale"
    echo ""
    echo "This script will:"
    echo "  1. Update system and enable automatic security updates"
    echo "  2. Install Docker with log rotation"
    echo "  3. Harden SSH (key-only, no root login)"
    echo "  4. Configure user '$USERNAME' with sudo + docker access"
    echo "  5. Configure firewall (Tailscale-only, all public ports blocked)"
    echo "  6. Create 2GB swap file"
    echo ""
    log_warn "Make sure you're connected via Tailscale IP: $TAILSCALE_IP"
    log_warn "Public IP access will be completely blocked!"
else
    log_warn "PUBLIC MODE: Ports 22, 80, 443 will be open to the internet"
    echo ""
    echo "This script will:"
    echo "  1. Update system and enable automatic security updates"
    echo "  2. Install Docker with log rotation"
    echo "  3. Harden SSH (key-only, no root login)"
    echo "  4. Configure user '$USERNAME' with sudo + docker access"
    echo "  5. Configure firewall (allow SSH, HTTP, HTTPS only)"
    echo "  6. Create 2GB swap file"
fi
echo ""

# =============================================================================
# STEP 1: System Updates
# =============================================================================
log_step "Step 1/6: Updating system..."

export DEBIAN_FRONTEND=noninteractive

# Prevent interactive prompts from needrestart
if [ -d /etc/needrestart ]; then
    mkdir -p /etc/needrestart/conf.d
    echo '$nrconf{restart} = "a";' > /etc/needrestart/conf.d/no-prompt.conf
fi

apt-get update
apt-get upgrade -y

# Install essentials
apt-get install -y git nano curl wget gnupg ca-certificates

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
log_step "Step 2/6: Installing Docker..."

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
log_info "Docker installed and configured"

# =============================================================================
# STEP 3: SSH Hardening
# =============================================================================
log_step "Step 3/6: Hardening SSH..."

# Backup original config (only once)
if [ ! -f /etc/ssh/sshd_config.backup ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
fi

# Disable password authentication
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Disable root login
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# Ensure key authentication is enabled
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Disable empty passwords
sed -i 's/^#PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

# Restart SSH (existing sessions stay alive)
systemctl restart sshd

log_info "SSH hardened: password auth disabled, root login disabled"

# =============================================================================
# STEP 4: Configure User
# =============================================================================
log_step "Step 4/6: Configuring user '$USERNAME'..."

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

# Allow sudo without password (convenient for scripts)
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"

log_info "User '$USERNAME' configured with sudo + docker access"

# =============================================================================
# STEP 5: Configure Firewall (iptables)
# =============================================================================
log_step "Step 5/6: Configuring firewall..."

# Install iptables-persistent (non-interactive)
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get install -y iptables-persistent

# -----------------------------------------------------------------------------
# IPv4 INPUT chain (host protection)
# -----------------------------------------------------------------------------
log_info "Configuring IPv4 firewall rules..."

# Flush existing INPUT rules
iptables -F INPUT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# Always allow Tailscale (harmless if not installed - interface won't exist)
iptables -A INPUT -i tailscale0 -j ACCEPT
iptables -A INPUT -p udp --dport 41641 -j ACCEPT

if [ "$MODE" = "public" ]; then
    # PUBLIC MODE: Also allow SSH, HTTP, HTTPS
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
fi

# Default policy: DROP everything else
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT

# -----------------------------------------------------------------------------
# FORWARD chain (for Docker)
# -----------------------------------------------------------------------------
iptables -F FORWARD 2>/dev/null || true
iptables -I FORWARD -s 172.16.0.0/12 -j ACCEPT
iptables -I FORWARD -d 172.16.0.0/12 -j ACCEPT
iptables -P FORWARD DROP

# -----------------------------------------------------------------------------
# DOCKER-USER chain (container access control)
# -----------------------------------------------------------------------------
log_info "Configuring Docker firewall rules..."

# Create DOCKER-USER chain if it doesn't exist
iptables -N DOCKER-USER 2>/dev/null || true

# Flush existing DOCKER-USER rules
iptables -F DOCKER-USER 2>/dev/null || true

# Allow established connections
iptables -I DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# Allow Docker internal traffic
iptables -I DOCKER-USER -i docker0 -j RETURN
iptables -I DOCKER-USER -s 172.16.0.0/12 -j RETURN
iptables -I DOCKER-USER -i br-+ -j RETURN

# Always allow Tailscale to reach containers (harmless if not installed)
iptables -I DOCKER-USER -i tailscale0 -j RETURN

if [ "$MODE" = "public" ]; then
    # PUBLIC MODE: Also allow web traffic to reach containers
    iptables -I DOCKER-USER -p tcp --dport 80 -j RETURN
    iptables -I DOCKER-USER -p tcp --dport 443 -j RETURN
fi

# Block everything else to containers (whitelist approach)
iptables -A DOCKER-USER -j DROP

# -----------------------------------------------------------------------------
# IPv6 (minimal rules, mostly blocked)
# -----------------------------------------------------------------------------
log_info "Configuring IPv6 firewall rules..."

ip6tables -F INPUT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
ip6tables -A INPUT -i tailscale0 -j ACCEPT  # Always allow (harmless if not installed)

ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# -----------------------------------------------------------------------------
# Save iptables rules
# -----------------------------------------------------------------------------
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

if [ "$MODE" = "private" ]; then
    log_info "Firewall configured: Tailscale-only access"
else
    log_info "Firewall configured: SSH (22), HTTP (80), HTTPS (443) + Tailscale"
fi

# =============================================================================
# STEP 6: Create Swap File
# =============================================================================
log_step "Step 6/6: Configuring swap..."

if [ -f /swapfile ] || [ "$(swapon --show | wc -l)" -gt 0 ]; then
    log_info "Swap already exists, skipping"
else
    fallocate -l 2G /swapfile
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
# Save mode and version
# =============================================================================
log_info "Saving configuration..."

echo "$MODE" > "$MODE_FILE"
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

    touch "$CHECK_FILE" 2>/dev/null

    if [ -n "$REMOTE_VERSION" ] && [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
        echo ""
        echo -e "\033[1;33m[vps-setup]\033[0m Update available: $LOCAL_VERSION → $REMOTE_VERSION"
        echo "  curl -O https://raw.githubusercontent.com/tetrixdev/vps-setup/main/setup.sh && sudo bash setup.sh"
        echo ""
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
if [ "$MODE" = "private" ]; then
    echo "Your server is now configured with:"
    echo "  ✓ Automatic security updates"
    echo "  ✓ Docker with log rotation (50MB × 5 files per container)"
    echo "  ✓ SSH: key-only, no root login"
    echo "  ✓ User '$USERNAME' with sudo + docker"
    echo "  ✓ Firewall: Tailscale-only (all public ports blocked)"
    echo "  ✓ 2GB swap file"
    echo ""
    echo "Connect via:"
    echo "  ssh $USERNAME@$TAILSCALE_IP"
else
    echo "Your server is now configured with:"
    echo "  ✓ Automatic security updates"
    echo "  ✓ Docker with log rotation (50MB × 5 files per container)"
    echo "  ✓ SSH: key-only, no root login"
    echo "  ✓ User '$USERNAME' with sudo + docker"
    echo "  ✓ Firewall: ports 22, 80, 443 + Tailscale"
    echo "  ✓ 2GB swap file"
    echo ""
    echo "Connect via:"
    echo "  ssh $USERNAME@<your-server-ip>"
fi
echo ""
echo "============================================================================="
echo ""
log_warn "IMPORTANT: Root login is now disabled."
log_warn "Test the new user login BEFORE closing this session!"
echo ""
echo "In a NEW terminal, run:"
echo "  ssh $USERNAME@<server-ip>"
echo ""
