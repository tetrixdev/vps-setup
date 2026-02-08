#!/bin/bash
# =============================================================================
# VPS Setup Script
# =============================================================================
#
# Secures a fresh Ubuntu/Debian server for hosting web applications or
# private development environments.
#
# MODES:
#   ./setup.sh            Public web server (ports 22, 80, 443 open)
#   ./setup.sh --private  Private server (Tailscale-only access)
#
# WHAT IT DOES:
#   1. Updates system and enables automatic security patches
#   2. Installs Docker with log rotation
#   3. Hardens SSH (key-only auth, no root login)
#   4. Creates a non-root user with sudo and docker access
#   5. Configures iptables firewall
#   6. Creates swap file (if none exists)
#
# PREREQUISITES:
#   - Fresh Ubuntu 24.04 or Debian 12 server
#   - SSH key already added (you'll be locked out without one!)
#   - For --private mode: Tailscale installed and connected first
#
# REPOSITORY: https://github.com/tetrixdev/vps-setup
#
# =============================================================================

set -e  # Exit on any error

SCRIPT_VERSION="1.0.0"
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

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}==>${NC} $1"; }

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
PRIVATE_MODE=false
SKIP_USER_CREATION=false
SKIP_CONFIRM=false
USERNAME="deploy"

while [[ $# -gt 0 ]]; do
    case $1 in
        --private)
            PRIVATE_MODE=true
            shift
            ;;
        --skip-user)
            SKIP_USER_CREATION=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
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
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --private      Tailscale-only mode (no public ports)"
            echo "  --username=X   Username to create (default: deploy)"
            echo "  --skip-user    Don't create a new user"
            echo "  -y, --yes      Skip confirmation prompt"
            echo "  -h, --help     Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
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

# Check for SSH key before we lock out password auth
if [ "$SKIP_USER_CREATION" = false ]; then
    if [ ! -f /root/.ssh/authorized_keys ] || [ ! -s /root/.ssh/authorized_keys ]; then
        log_error "No SSH keys found in /root/.ssh/authorized_keys"
        log_error "Add your SSH key first, or you'll be locked out!"
        echo ""
        echo "To add your SSH key:"
        echo "  1. On your LOCAL machine, run: cat ~/.ssh/id_ed25519.pub"
        echo "  2. On this server, run:"
        echo "     mkdir -p ~/.ssh && echo 'YOUR_KEY_HERE' >> ~/.ssh/authorized_keys"
        echo ""
        exit 1
    fi
    log_info "SSH key found - safe to proceed"
else
    log_warn "Skipping user creation - ensure your existing user has SSH keys!"
fi

# Private mode requires Tailscale
if [ "$PRIVATE_MODE" = true ]; then
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

# Detect if Tailscale is present (for optional rules in public mode)
TAILSCALE_INSTALLED=false
if command -v tailscale &> /dev/null && tailscale status &> /dev/null 2>&1; then
    TAILSCALE_INSTALLED=true
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
fi

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
echo ""
if [ "$PRIVATE_MODE" = true ]; then
    log_warn "PRIVATE MODE: Server will only be accessible via Tailscale"
    echo ""
    echo "This script will:"
    echo "  1. Update system and enable automatic security updates"
    echo "  2. Install Docker with log rotation"
    echo "  3. Harden SSH (key-only, no root login)"
    echo "  4. Create user '$USERNAME' with sudo + docker access"
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
    echo "  4. Create user '$USERNAME' with sudo + docker access"
    echo "  5. Configure firewall (allow SSH, HTTP, HTTPS only)"
    echo "  6. Create 2GB swap file"
    if [ "$TAILSCALE_INSTALLED" = true ]; then
        echo ""
        echo "  Tailscale detected - will also allow Tailscale traffic"
    fi
fi

if [ "$SKIP_CONFIRM" = false ]; then
    echo ""
    read -p "Proceed? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Aborted."
        exit 0
    fi
fi

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

# Configure Docker daemon (log rotation)
log_info "Configuring Docker log rotation..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
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
# STEP 4: Create Non-Root User
# =============================================================================
log_step "Step 4/6: Creating user '$USERNAME'..."

if [ "$SKIP_USER_CREATION" = true ]; then
    log_info "Skipping user creation (--skip-user)"
else
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

    # Copy SSH keys from root
    USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
    mkdir -p "$USER_HOME/.ssh"
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"

    # Allow sudo without password (convenient for scripts)
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
    chmod 440 "/etc/sudoers.d/$USERNAME"

    log_info "User '$USERNAME' configured with sudo + docker access"
fi

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

if [ "$PRIVATE_MODE" = true ]; then
    # PRIVATE MODE: Tailscale only
    iptables -A INPUT -i tailscale0 -j ACCEPT
    iptables -A INPUT -p udp --dport 41641 -j ACCEPT
else
    # PUBLIC MODE: Allow SSH, HTTP, HTTPS
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # If Tailscale is installed, allow it too
    if [ "$TAILSCALE_INSTALLED" = true ]; then
        iptables -A INPUT -i tailscale0 -j ACCEPT
        iptables -A INPUT -p udp --dport 41641 -j ACCEPT
        log_info "Tailscale rules added (detected installation)"
    fi
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

# Create DOCKER-USER chain if it doesn't exist (Docker creates it on first container)
iptables -N DOCKER-USER 2>/dev/null || true

# Flush existing DOCKER-USER rules
iptables -F DOCKER-USER 2>/dev/null || true

# Allow established connections
iptables -I DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN

# Allow Docker internal traffic
iptables -I DOCKER-USER -i docker0 -j RETURN
iptables -I DOCKER-USER -s 172.16.0.0/12 -j RETURN
iptables -I DOCKER-USER -i br-+ -j RETURN

if [ "$PRIVATE_MODE" = true ]; then
    # PRIVATE MODE: Only Tailscale can reach containers
    iptables -I DOCKER-USER -i tailscale0 -j RETURN
else
    # PUBLIC MODE: Allow web traffic to reach containers
    iptables -I DOCKER-USER -p tcp --dport 80 -j RETURN
    iptables -I DOCKER-USER -p tcp --dport 443 -j RETURN

    # If Tailscale installed, allow it to reach containers too
    if [ "$TAILSCALE_INSTALLED" = true ]; then
        iptables -I DOCKER-USER -i tailscale0 -j RETURN
    fi
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

if [ "$PRIVATE_MODE" = true ]; then
    ip6tables -A INPUT -i tailscale0 -j ACCEPT
elif [ "$TAILSCALE_INSTALLED" = true ]; then
    ip6tables -A INPUT -i tailscale0 -j ACCEPT
fi

ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# -----------------------------------------------------------------------------
# Save iptables rules
# -----------------------------------------------------------------------------
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

if [ "$PRIVATE_MODE" = true ]; then
    log_info "Firewall configured: Tailscale-only access"
else
    log_info "Firewall configured: SSH (22), HTTP (80), HTTPS (443) open"
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
# Version Tracking & Update Checker
# =============================================================================
log_info "Setting up version tracking..."

# Save current version
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
if [ "$PRIVATE_MODE" = true ]; then
    echo "Your server is now configured with:"
    echo "  ✓ Automatic security updates"
    echo "  ✓ Docker with log rotation"
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
    echo "  ✓ Docker with log rotation"
    echo "  ✓ SSH: key-only, no root login"
    echo "  ✓ User '$USERNAME' with sudo + docker"
    echo "  ✓ Firewall: only ports 22, 80, 443 open"
    echo "  ✓ 2GB swap file"
    echo ""
    echo "Connect via:"
    echo "  ssh $USERNAME@<your-server-ip>"
fi
echo ""
echo "============================================================================="

if [ "$SKIP_USER_CREATION" = false ]; then
    echo ""
    log_warn "IMPORTANT: Root login is now disabled."
    log_warn "Test the new user login BEFORE closing this session!"
    echo ""
    echo "In a NEW terminal, run:"
    echo "  ssh $USERNAME@<server-ip>"
    echo ""
fi
