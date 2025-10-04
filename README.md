# Bitcoin Core Node on Raspberry Pi 5

A Docker containerized Bitcoin Core Node optimized for Raspberry Pi 5 with Ubuntu Server and 1TB SSD storage.

## Overview

This project provides a complete setup for running a Bitcoin Core full node on a Raspberry Pi 5 using Docker containers. The setup is optimized for ARM64 architecture and includes monitoring, backup solutions, and system optimizations.

## Hardware Requirements

- **Raspberry Pi 5** (4GB+ RAM recommended)
- **1TB SSD** (external USB 3.0 or NVMe via PCIe)
- **Reliable power supply** (27W USB-C PD)
- **Active cooling** (fan or heatsink)
- **Stable internet connection**

## Software Requirements

- **Ubuntu Server 22.04 LTS** (ARM64)
- **Docker Engine**
- **Docker Compose**

## Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd raspiservers
   ```

2. Prepare your system:
   ```bash
   sudo ./scripts/system-setup.sh
   ```

3. Configure Bitcoin Core:
   ```bash
   cp config/bitcoin.conf.example config/bitcoin.conf
   # Edit config/bitcoin.conf as needed
   ```

4. Start the Bitcoin node:
   ```bash
   docker-compose up -d
   ```

5. Monitor the sync process:
   ```bash
   ./scripts/monitor.sh
   ```

## Project Structure

```
├── README.md                 # This file
├── docker/
│   ├── Dockerfile            # Bitcoin Core container
│   └── docker-compose.yml    # Container orchestration
├── config/
│   ├── bitcoin.conf          # Bitcoin Core configuration
│   └── bitcoin.conf.example  # Configuration template
├── scripts/
│   ├── system-setup.sh       # Ubuntu system optimization
│   ├── deploy.sh            # Deployment script
│   ├── monitor.sh           # Node monitoring
│   ├── backup.sh            # Backup solution
│   └── update.sh            # Update script
├── data/                    # Bitcoin blockchain data (mounted volume)
└── logs/                    # Application logs
```

## Features

- **Multi-stage Docker build** optimized for ARM64
- **Persistent data storage** with proper volume mounting
- **Automated backups** of wallet and configuration
- **Real-time monitoring** of node status and sync progress
- **System optimizations** for Raspberry Pi 5
- **Security hardening** with non-root containers
- **Resource monitoring** and alerting

## Initial Blockchain Sync

The initial blockchain download (IBD) will take several days to weeks depending on your internet connection. The Bitcoin blockchain is currently ~500GB+ in size.

Expected sync times:
- **Fast connection (100+ Mbps)**: 3-7 days
- **Medium connection (50 Mbps)**: 1-2 weeks
- **Slow connection (<25 Mbps)**: 2-4 weeks

## Security Considerations

- Node runs in a containerized environment
- No wallet functionality enabled by default
- RPC access restricted to localhost
- Regular security updates via automated scripts

## Monitoring

Monitor your node status:
```bash
# Check sync progress
./scripts/monitor.sh

# View logs
docker-compose logs -f bitcoin-node

# Check system resources
htop
```

## Maintenance

```bash
# Update Bitcoin Core
./scripts/update.sh

# Backup wallet and config
./scripts/backup.sh

# Check disk usage
df -h
```

## Troubleshooting

Common issues and solutions:

1. **Slow sync**: Ensure SSD is properly mounted and has sufficient space
2. **High CPU usage**: Normal during sync, will decrease after IBD
3. **Network issues**: Check port forwarding for port 8333
4. **Docker issues**: Restart with `docker-compose restart`

## Resources

- [Bitcoin Core Documentation](https://bitcoin.org/en/bitcoin-core/)
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/)
- [Docker Documentation](https://docs.docker.com/)

## License

This project is open source and available under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.