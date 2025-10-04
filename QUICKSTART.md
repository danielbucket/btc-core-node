# Quick Start Guide - Bitcoin Core Node on Raspberry Pi 5

This quick start guide will get your Bitcoin Core node up and running in minimal time.

## Prerequisites

- Raspberry Pi 5 (4GB+ RAM)
- 1TB SSD (USB 3.0 or NVMe)
- Ubuntu Server 22.04 LTS (ARM64) installed
- Stable internet connection

## Step 1: Initial System Setup

Run the automated system setup script:

```bash
# Clone this repository
git clone <repository-url>
cd raspiservers

# Run system setup (this installs Docker, optimizes system, configures firewall)
./scripts/system-setup.sh

# Reboot system
sudo reboot
```

## Step 2: Configure Bitcoin Core

```bash
# Navigate to project directory
cd raspiservers

# Edit Bitcoin configuration
nano config/bitcoin.conf

# IMPORTANT: Change the RPC password from "CHANGEME-secure-password-123" to something secure
```

## Step 3: Deploy Bitcoin Node

```bash
# Deploy the Bitcoin Core node (this will build and start the container)
./scripts/deploy.sh

# This process takes 30-60 minutes on Raspberry Pi 5 for the initial build
```

## Step 4: Monitor Sync Progress

```bash
# Check sync status
./scripts/monitor.sh

# View real-time logs
./scripts/monitor.sh logs

# Continuous monitoring
./scripts/monitor.sh watch
```

## Step 5: Setup Backups (Optional)

```bash
# Create manual backup
./scripts/backup.sh

# Setup automatic daily backups
./scripts/backup.sh schedule
```

## Important Notes

- **Initial sync takes 3-21 days** depending on your internet speed
- **Port 8333 should be open** for optimal P2P connectivity
- **Monitor disk space** - the blockchain is ~500GB+ and growing
- **Keep the Pi cool** - ensure adequate ventilation or active cooling

## Common Commands

```bash
# Check node status
./scripts/monitor.sh

# Stop the node
./scripts/deploy.sh stop

# Start the node
./scripts/deploy.sh start

# Restart the node
./scripts/deploy.sh restart

# View logs
./scripts/deploy.sh logs

# Update Bitcoin Core
./scripts/update.sh

# Create backup
./scripts/backup.sh
```

## Troubleshooting

If you encounter issues:

1. **Container won't start**: Check logs with `./scripts/deploy.sh logs`
2. **Slow sync**: Ensure SSD is properly mounted and has sufficient space
3. **High CPU**: Normal during initial sync, should decrease after IBD
4. **Network issues**: Check firewall settings and port forwarding

For detailed troubleshooting, see `UBUNTU_OPTIMIZATION.md`.

## Next Steps

- Set up monitoring dashboards (optional)
- Configure automated updates
- Set up external monitoring/alerting
- Consider Lightning Network integration

## Security Reminder

- Change the default RPC password in `config/bitcoin.conf`
- Keep your system updated
- Use SSH keys instead of passwords
- Consider VPN access for remote management
