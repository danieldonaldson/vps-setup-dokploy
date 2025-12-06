#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
SSH_PUBLIC_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICdRA0uJzU//4YNgMagVBjIHaX8961nTv0Os8bnF831P daniel@Daniel-PC"
ADMIN_USER="deploy"
SSH_PORT="88"
TIMEZONE="Africa/Johannesburg"

echo "=== Starting secure Dokploy setup ==="

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
# Idempotent SSH config updates
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
ufw allow $SSH_PORT/tcp 2>/dev/null || true  # SSH (custom port)
ufw allow 80/tcp 2>/dev/null || true         # HTTP
ufw allow 443/tcp 2>/dev/null || true        # HTTPS
ufw allow 3000/tcp 2>/dev/null || true       # Dokploy UI (remove after setting up domain)
ufw --force enable
echo "✓ Firewall configured"

# === FAIL2BAN ===
apt install -y fail2ban
systemctl enable fail2ban
if systemctl is-active --quiet fail2ban; then
    systemctl restart fail2ban
    echo "✓ Fail2ban restarted"
else
    systemctl start fail2ban
    echo "✓ Fail2ban installed and started"
fi

# === AUTOMATIC SECURITY UPDATES ===
apt install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
echo "✓ Automatic security updates enabled"

# === INSTALL DOKPLOY ===
if command -v dokploy &>/dev/null || docker ps --format '{{.Names}}' 2>/dev/null | grep -q dokploy; then
    echo "✓ Dokploy already installed (skipping)"
else
    echo "=== Installing Dokploy ==="
    curl -sSL https://dokploy.com/install.sh | sh
fi

echo ""
echo "============================================"
echo "=== Setup complete! ==="
echo "============================================"
echo ""
echo "1. Wait 15-30 seconds for Dokploy to start"
echo "2. Access Dokploy at: http://YOUR_SERVER_IP:3000"
echo "3. Create your admin account"
echo "4. Set up a domain for Dokploy itself and enable Let's Encrypt"
echo "5. Then remove port 3000 from firewall:"
echo "   sudo ufw delete allow 3000/tcp"
echo ""
echo "SSH access: ssh -p $SSH_PORT $ADMIN_USER@YOUR_SERVER_IP"
echo ""
echo "Next steps:"
echo "- Deploy rust-captcha-verification app via Dokploy"
echo "- Set up Netdata monitoring (see MIGRATION.md)"
echo "- Configure any required environment variables"
echo "============================================"
