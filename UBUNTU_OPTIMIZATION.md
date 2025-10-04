# Ubuntu Server Optimization Guide for Bitcoin Core on Raspberry Pi 5

This guide provides comprehensive system optimizations for running a Bitcoin Core node on Ubuntu Server 22.04 LTS on a Raspberry Pi 5 with 1TB SSD storage.

## Table of Contents

1. [Hardware Setup](#hardware-setup)
2. [Initial Ubuntu Server Setup](#initial-ubuntu-server-setup)
3. [SSD Configuration](#ssd-configuration)
4. [System Optimizations](#system-optimizations)
5. [Network Optimizations](#network-optimizations)
6. [Security Hardening](#security-hardening)
7. [Performance Monitoring](#performance-monitoring)
8. [Troubleshooting](#troubleshooting)

## Hardware Setup

### Raspberry Pi 5 Requirements

- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 1TB SSD (USB 3.0 or NVMe via PCIe)
- **Power**: 27W USB-C PD power supply
- **Cooling**: Active cooling (fan) strongly recommended
- **Network**: Gigabit Ethernet preferred over Wi-Fi

### SSD Recommendations

**Best Options:**

- Samsung T7 (USB 3.2)
- WD Black P50 Game Drive (USB 3.2)
- Crucial X8 (USB 3.2)
- Any NVMe SSD with PCIe hat

**Format**: ext4 with `noatime` mount option

## Initial Ubuntu Server Setup

### 1. Flash Ubuntu Server 22.04 LTS ARM64

```bash
# Download from: https://ubuntu.com/download/raspberry-pi
# Use Raspberry Pi Imager or dd to flash to SD card
```

### 2. Initial Boot Configuration

Edit `/boot/firmware/config.txt` on the SD card before first boot:

```ini
# Enable 64-bit mode
arm_64bit=1

# GPU memory split (minimize for headless server)
gpu_mem=16

# Disable Wi-Fi and Bluetooth if using Ethernet
dtoverlay=disable-wifi
dtoverlay=disable-bt

# Enable PCIe (for NVMe SSDs)
dtparam=pciex1

# Overclock settings (optional, ensure adequate cooling)
over_voltage=2
arm_freq=2400

# USB power settings
max_usb_current=1
```

### 3. First Boot Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y curl wget git htop iotop tree vim ufw fail2ban

# Set timezone
sudo timedatectl set-timezone UTC
```

## SSD Configuration

### 1. Format and Mount SSD

```bash
# Identify your SSD (usually /dev/sda)
lsblk

# Format with ext4
sudo mkfs.ext4 -L bitcoin-data /dev/sda1

# Create mount point
sudo mkdir -p /mnt/bitcoin-data

# Mount temporarily
sudo mount /dev/sda1 /mnt/bitcoin-data

# Set ownership
sudo chown -R $USER:$USER /mnt/bitcoin-data
```

### 2. Permanent Mount

Add to `/etc/fstab`:

```bash
# Bitcoin SSD mount
LABEL=bitcoin-data /mnt/bitcoin-data ext4 defaults,noatime,errors=remount-ro 0 2
```

### 3. Test Mount

```bash
# Test the fstab entry
sudo mount -a

# Verify mount
df -h /mnt/bitcoin-data
```

## System Optimizations

### 1. Memory Management

Edit `/etc/sysctl.d/99-bitcoin.conf`:

```ini
# Memory optimizations for Bitcoin Core
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.min_free_kbytes = 65536

# Increase file descriptor limits
fs.file-max = 1048576
fs.nr_open = 1048576
```

### 2. Network Stack Optimization

Add to `/etc/sysctl.d/99-bitcoin.conf`:

```ini
# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# TCP optimization
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 7
net.ipv4.tcp_keepalive_intvl = 30

# Connection tracking
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
```

### 3. File Descriptor Limits

Edit `/etc/security/limits.conf`:

```ini
# Bitcoin Core optimizations
* soft nofile 1048576
* hard nofile 1048576
bitcoin soft nofile 1048576
bitcoin hard nofile 1048576
```

### 4. Swap Configuration

```bash
# Create 4GB swap file on SSD
sudo fallocate -l 4G /mnt/bitcoin-data/swapfile
sudo chmod 600 /mnt/bitcoin-data/swapfile
sudo mkswap /mnt/bitcoin-data/swapfile

# Add to fstab
echo '/mnt/bitcoin-data/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Enable swap
sudo swapon /mnt/bitcoin-data/swapfile
```

### 5. I/O Scheduler Optimization

```bash
# Set I/O scheduler for SSD
echo 'SUBSYSTEM=="block", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"' | sudo tee /etc/udev/rules.d/60-ssd-scheduler.rules
```

### 6. CPU Governor

```bash
# Set performance governor
echo 'performance' | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Make permanent
echo 'GOVERNOR="performance"' | sudo tee -a /etc/default/cpufrequtils
```

## Network Optimizations

### 1. Disable Unnecessary Services

```bash
# Disable unnecessary services
sudo systemctl disable bluetooth
sudo systemctl disable wpa_supplicant  # if using Ethernet
sudo systemctl disable avahi-daemon
sudo systemctl disable cups-browsed
```

### 2. Network Interface Optimization

Edit `/etc/netplan/50-cloud-init.yaml`:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      dhcp6: false
      optional: true
      # Optimize for Bitcoin P2P
      receive-checksum-offload: true
      transmit-checksum-offload: true
      tcp-segmentation-offload: true
      generic-segmentation-offload: true
```

Apply changes:

```bash
sudo netplan apply
```

### 3. Firewall Configuration

```bash
# Reset UFW
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Allow Bitcoin P2P
sudo ufw allow 8333/tcp comment 'Bitcoin P2P'

# Allow from Docker subnet
sudo ufw allow from 172.16.0.0/12

# Enable firewall
sudo ufw --force enable
```

## Security Hardening

### 1. SSH Security

Edit `/etc/ssh/sshd_config`:

```ini
# SSH hardening
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

### 2. Fail2Ban Configuration

Edit `/etc/fail2ban/jail.local`:

```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
```

### 3. Automatic Security Updates

```bash
# Enable automatic security updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

## Performance Monitoring

### 1. System Monitoring Tools

```bash
# Install monitoring tools
sudo apt install -y htop iotop nethogs iftop sysstat

# Enable sysstat
sudo systemctl enable sysstat
```

### 2. Custom Monitoring Script

Create `/usr/local/bin/bitcoin-monitor`:

```bash
#!/bin/bash

# System resource monitoring for Bitcoin Core

echo "=== Bitcoin Node System Monitor ==="
echo "Date: $(date)"
echo ""

echo "CPU Usage:"
top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1

echo ""
echo "Memory Usage:"
free -h

echo ""
echo "Disk Usage:"
df -h /mnt/bitcoin-data

echo ""
echo "Network Connections:"
ss -tuln | grep -E ':(8333|8332)'

echo ""
echo "Load Average:"
uptime

echo ""
echo "Top Processes:"
ps aux --sort=-%cpu | head -10
```

Make executable and add to cron:

```bash
sudo chmod +x /usr/local/bin/bitcoin-monitor

# Add to crontab (every hour)
echo "0 * * * * /usr/local/bin/bitcoin-monitor >> /var/log/bitcoin-monitor.log" | crontab -
```

### 3. Temperature Monitoring

```bash
# Check CPU temperature
vcgencmd measure_temp

# Continuous monitoring
watch -n 5 'vcgencmd measure_temp'
```

## Troubleshooting

### Common Issues and Solutions

#### 1. High CPU Temperature

```bash
# Check temperature
vcgencmd measure_temp

# Solutions:
# - Add active cooling (fan)
# - Reduce overclocking
# - Improve case ventilation
```

#### 2. Slow Sync Performance

```bash
# Check disk I/O
iotop -a

# Optimize Bitcoin Core settings in bitcoin.conf:
dbcache=1024        # Increase if you have 8GB RAM
par=3               # Use 3 CPU cores for verification
```

#### 3. Network Connectivity Issues

```bash
# Check Bitcoin P2P port
sudo netstat -tuln | grep 8333

# Test external connectivity
telnet [your-external-ip] 8333

# Check firewall
sudo ufw status verbose
```

#### 4. Memory Issues

```bash
# Check memory usage
free -h

# Check swap usage
swapon --show

# Monitor memory pressure
dmesg | grep -i "out of memory"
```

#### 5. Disk Space Issues

```bash
# Check Bitcoin data size
du -sh /mnt/bitcoin-data

# Enable pruning in bitcoin.conf
prune=50000  # Keep last 50GB of blocks
```

### Performance Benchmarks

**Expected Performance on Raspberry Pi 5:**

- **Initial Sync**: 7-21 days (depending on internet speed)
- **CPU Usage**: 50-80% during sync, 10-30% when synced
- **Memory Usage**: 1-2GB
- **Disk I/O**: 50-100 MB/s during sync
- **Network**: 10-50 Mbps during sync

### Optimization Checklist

- [ ] SSD properly mounted with `noatime`
- [ ] Swap file configured on SSD
- [ ] System parameters optimized
- [ ] Network stack tuned
- [ ] Firewall configured
- [ ] Security hardening applied
- [ ] Monitoring tools installed
- [ ] Temperature monitoring active
- [ ] Automatic updates enabled
- [ ] Bitcoin Core configuration optimized

### Advanced Optimizations

#### 1. ZRAM (Alternative to swap file)

```bash
# Install zram-tools
sudo apt install zram-tools

# Configure in /etc/default/zramswap
echo 'ALGO=lz4' | sudo tee -a /etc/default/zramswap
echo 'PERCENT=25' | sudo tee -a /etc/default/zramswap
```

#### 2. Custom Kernel Parameters

Add to `/boot/firmware/cmdline.txt`:

```
cgroup_enable=memory swapaccount=1 cgroup_memory=1
```

#### 3. Real-time Process Priority

```bash
# Give Bitcoin Core higher priority
echo 'bitcoin soft priority 10' | sudo tee -a /etc/security/limits.conf
echo 'bitcoin hard priority 10' | sudo tee -a /etc/security/limits.conf
```

This optimization guide should provide a solid foundation for running Bitcoin Core efficiently on your Raspberry Pi 5 setup.
