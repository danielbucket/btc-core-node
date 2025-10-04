#!/bin/bash

# System setup script for Bitcoin Core node on Raspberry Pi 5
# Run this script on a fresh Ubuntu Server installation

set -e

echo "🚀 Setting up Raspberry Pi 5 for Bitcoin Core node..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "❌ This script should not be run as root"
   exit 1
fi

# Update system
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install required packages
echo "📦 Installing required packages..."
sudo apt install -y \
    curl \
    wget \
    git \
    htop \
    iotop \
    tree \
    vim \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential

# Install Docker
echo "🐳 Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    echo "✅ Docker installed successfully"
else
    echo "✅ Docker already installed"
fi

# Install Docker Compose (standalone)
echo "🐳 Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "✅ Docker Compose installed successfully"
else
    echo "✅ Docker Compose already installed"
fi

# Configure firewall
echo "🔥 Configuring firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Allow Bitcoin P2P port
sudo ufw allow 8333/tcp comment 'Bitcoin P2P'

# Allow Docker subnet
sudo ufw allow from 172.16.0.0/12 to any

sudo ufw --force enable
echo "✅ Firewall configured"

# Configure fail2ban
echo "🛡️  Configuring fail2ban..."
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Enable automatic security updates
echo "🔄 Enabling automatic security updates..."
sudo dpkg-reconfigure -plow unattended-upgrades

# Optimize system for Bitcoin node
echo "⚡ Applying system optimizations..."

# Increase file descriptor limits
cat << 'EOF' | sudo tee -a /etc/security/limits.conf
# Bitcoin Core optimizations
bitcoin soft nofile 1048576
bitcoin hard nofile 1048576
* soft nofile 1048576
* hard nofile 1048576
EOF

# Optimize sysctl parameters
cat << 'EOF' | sudo tee /etc/sysctl.d/99-bitcoin.conf
# Bitcoin Core network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30

# Memory optimizations
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# File system optimizations
fs.file-max = 1048576
EOF

sudo sysctl --system

# Configure swap (important for memory-constrained Pi)
echo "💾 Configuring swap..."
if [[ ! -f /swapfile ]]; then
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "✅ 4GB swap file created"
else
    echo "✅ Swap file already exists"
fi

# Check SSD mount
echo "💽 Checking SSD configuration..."
BITCOIN_DATA_DIR="/home/$USER/bitcoin-node/data"

if ! mountpoint -q "$BITCOIN_DATA_DIR" 2>/dev/null; then
    echo "⚠️  Warning: Bitcoin data directory is not on a separate mount point"
    echo "   Make sure your 1TB SSD is properly mounted to store blockchain data"
    echo "   You may want to mount your SSD to: $BITCOIN_DATA_DIR"
    echo ""
    echo "   Example commands to mount SSD (adjust device as needed):"
    echo "   sudo mkdir -p $BITCOIN_DATA_DIR"
    echo "   sudo mount /dev/sda1 $BITCOIN_DATA_DIR"
    echo "   sudo chown -R $USER:$USER $BITCOIN_DATA_DIR"
    echo ""
    echo "   Add to /etc/fstab for persistent mounting:"
    echo "   /dev/sda1 $BITCOIN_DATA_DIR ext4 defaults,noatime 0 2"
fi

# Create systemd service for Docker Compose
echo "🔄 Creating systemd service..."
cat << EOF | sudo tee /etc/systemd/system/bitcoin-node.service
[Unit]
Description=Bitcoin Core Node
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/$USER/raspiservers
ExecStart=/usr/local/bin/docker-compose -f docker/docker-compose.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker/docker-compose.yml down
TimeoutStartSec=0
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable bitcoin-node.service

echo ""
echo "🎉 System setup completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Reboot your system: sudo reboot"
echo "2. After reboot, clone this repository"
echo "3. Configure your bitcoin.conf file"
echo "4. Run: cd raspiservers && ./scripts/deploy.sh"
echo ""
echo "⚠️  Important notes:"
echo "- Make sure your 1TB SSD is properly mounted"
echo "- Change the RPC password in config/bitcoin.conf"
echo "- Initial blockchain sync will take several days"
echo ""
echo "🔧 System information:"
echo "- Docker version: $(docker --version 2>/dev/null || echo 'Not available (reboot required)')"
echo "- Available disk space: $(df -h / | awk 'NR==2{print $4}')"
echo "- Available memory: $(free -h | awk 'NR==2{print $7}')"