#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbxQC8uUbv+JfBeGnfTa/EXq+cOaXBdZYtd/LLCnYGT deft_pangolin"
ADMIN_USER="deploy"
SSH_PORT="88"
TIMEZONE="Africa/Johannesburg"
PANGOLIN_INSTALL_DIR="/opt/pangolin"

echo "=== Starting secure Pangolin setup ==="

# === SYSTEM SETUP ===
apt update && apt upgrade -y

# Set timezone
timedatectl set-timezone "$TIMEZONE"
echo "✓ Timezone set to $TIMEZONE"

# Create non-root user (skip if exists)
if ! id "$ADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
    echo "✓ Created user $ADMIN_USER"
else
    echo "✓ User $ADMIN_USER already exists"
fi
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$ADMIN_USER

# SSH key for admin user
mkdir -p /home/$ADMIN_USER/.ssh
echo "$SSH_PUBLIC_KEY" > /home/$ADMIN_USER/.ssh/authorized_keys
chmod 700 /home/$ADMIN_USER/.ssh
chmod 600 /home/$ADMIN_USER/.ssh/authorized_keys
chown -R $ADMIN_USER:$ADMIN_USER /home/$ADMIN_USER/.ssh

# === HARDEN SSH ===
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    sed -i 's/^#\?Port .*/Port '"$SSH_PORT"'/' /etc/ssh/sshd_config
fi
if ! grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
    sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
fi
if ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
fi
# Restart SSH service (name varies by distro)
if systemctl list-units --full -all | grep -q "ssh.service"; then
    systemctl restart ssh
elif systemctl list-units --full -all | grep -q "sshd.service"; then
    systemctl restart sshd
fi
echo "✓ SSH hardened (Port: $SSH_PORT, Root login disabled, Password auth disabled)"

# === FIREWALL ===
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
# Add rules only if they don't exist
ufw allow $SSH_PORT/tcp 2>/dev/null || true    # SSH (custom port)
ufw allow 80/tcp 2>/dev/null || true           # HTTP
ufw allow 443/tcp 2>/dev/null || true          # HTTPS
ufw allow 51820/udp 2>/dev/null || true        # Gerbil WireGuard tunneling
ufw allow 21820/udp 2>/dev/null || true        # Gerbil secondary port
ufw --force enable
echo "✓ Firewall configured (ports: $SSH_PORT/tcp, 80/tcp, 443/tcp, 51820/udp, 21820/udp)"

# === CROWDSEC ===
# CrowdSec is recommended by Pangolin and replaces fail2ban with crowd-sourced threat intelligence
if ! command -v cscli &>/dev/null; then
    echo "=== Installing CrowdSec ==="
    curl -s https://install.crowdsec.net | sh
    apt install -y crowdsec crowdsec-firewall-bouncer-iptables
    systemctl enable crowdsec
    systemctl start crowdsec
    echo "✓ CrowdSec installed and started"
else
    echo "✓ CrowdSec already installed"
fi

# === AUTOMATIC SECURITY UPDATES ===
apt install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
echo "✓ Automatic security updates enabled"

# === INSTALL DOCKER (if not present) ===
if ! command -v docker &>/dev/null; then
    echo "=== Installing Docker ==="
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker $ADMIN_USER
    echo "✓ Docker installed"
else
    echo "✓ Docker already installed"
fi

# === INSTALL PANGOLIN ===
echo "=== Installing Pangolin ==="

# Create installation directory
mkdir -p "$PANGOLIN_INSTALL_DIR"
cd "$PANGOLIN_INSTALL_DIR"

# Download the Pangolin installer
if [ ! -f "$PANGOLIN_INSTALL_DIR/installer" ]; then
    curl -fsSL https://static.pangolin.net/get-installer.sh | bash
    echo "✓ Pangolin installer downloaded to $PANGOLIN_INSTALL_DIR"
else
    echo "✓ Pangolin installer already present"
fi

echo ""
echo "============================================"
echo "=== Pre-installation setup complete! ==="
echo "============================================"
echo ""
echo "NEXT STEPS TO COMPLETE PANGOLIN INSTALLATION:"
echo ""
echo "1. Ensure your domain is pointing to this server's IP"
echo ""
echo "2. Run the Pangolin installer:"
echo "   cd $PANGOLIN_INSTALL_DIR && sudo ./installer"
echo ""
echo "3. During installation, you'll be prompted for:"
echo "   - Base domain (e.g., example.com)"
echo "   - Dashboard subdomain (default: pangolin.example.com)"
echo "   - Email for Let's Encrypt SSL certificates"
echo "   - Whether to install Gerbil tunneling (recommended: yes)"
echo "   - Optional: SMTP settings"
echo "   - CrowdSec: say NO (already installed above)"
echo ""
echo "4. After installation completes, access your dashboard at:"
echo "   https://pangolin.YOUR_DOMAIN/auth/initial-setup"
echo ""
echo "5. Create your admin account and first organization"
echo ""
echo "SSH access: ssh -p $SSH_PORT $ADMIN_USER@YOUR_SERVER_IP"
echo ""
echo "============================================"
