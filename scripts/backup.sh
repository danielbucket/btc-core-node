#!/bin/bash

# Bitcoin Core Node Backup Script
# This script creates backups of configuration and wallet data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="/home/$(whoami)/bitcoin-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="bitcoin_backup_$DATE"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory..."
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"
    log_success "Backup directory created: $BACKUP_DIR/$BACKUP_NAME"
}

# Backup configuration files
backup_config() {
    log_info "Backing up configuration files..."
    
    # Copy configuration
    cp config/bitcoin.conf "$BACKUP_DIR/$BACKUP_NAME/"
    cp config/bitcoin.conf.example "$BACKUP_DIR/$BACKUP_NAME/"
    
    # Copy Docker files
    cp -r docker "$BACKUP_DIR/$BACKUP_NAME/"
    
    # Copy scripts
    cp -r scripts "$BACKUP_DIR/$BACKUP_NAME/"
    
    # Copy README
    cp README.md "$BACKUP_DIR/$BACKUP_NAME/"
    
    log_success "Configuration files backed up"
}

# Backup wallet data (if wallet is enabled)
backup_wallet() {
    if docker ps | grep -q bitcoin-core-node; then
        log_info "Checking for wallet data..."
        
        # Check if wallet is enabled
        if docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getwalletinfo 2>/dev/null; then
            log_info "Backing up wallet data..."
            
            # Stop the node temporarily for safe backup
            log_warning "Stopping Bitcoin node for safe wallet backup..."
            cd docker
            docker-compose stop bitcoin-node
            cd ..
            
            # Backup wallet files
            if [[ -d "data/wallets" ]]; then
                cp -r data/wallets "$BACKUP_DIR/$BACKUP_NAME/"
                log_success "Wallet data backed up"
            fi
            
            # Restart the node
            log_info "Restarting Bitcoin node..."
            cd docker
            docker-compose start bitcoin-node
            cd ..
            log_success "Bitcoin node restarted"
        else
            log_info "No wallet found (wallet disabled)"
        fi
    else
        log_warning "Bitcoin Core container is not running"
    fi
}

# Backup blockchain headers and chainstate (for quick restore)
backup_chainstate() {
    log_info "Backing up chainstate (this may take a while)..."
    
    if [[ -d "data/chainstate" ]]; then
        # Create compressed backup of chainstate
        tar -czf "$BACKUP_DIR/$BACKUP_NAME/chainstate_$DATE.tar.gz" -C data chainstate
        log_success "Chainstate backed up"
    else
        log_warning "Chainstate directory not found"
    fi
}

# Create system info snapshot
backup_system_info() {
    log_info "Creating system information snapshot..."
    
    local info_file="$BACKUP_DIR/$BACKUP_NAME/system_info.txt"
    
    {
        echo "Bitcoin Core Backup Information"
        echo "================================"
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "OS: $(uname -a)"
        echo ""
        
        echo "Docker Version:"
        docker --version
        echo ""
        
        echo "Docker Compose Version:"
        docker-compose --version
        echo ""
        
        echo "Container Status:"
        docker ps | grep bitcoin || echo "No Bitcoin containers running"
        echo ""
        
        echo "Disk Usage:"
        df -h ./data 2>/dev/null || df -h .
        echo ""
        
        echo "Bitcoin Core Version (if running):"
        if docker ps | grep -q bitcoin-core-node; then
            docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getnetworkinfo | jq -r '.subversion' || echo "Could not retrieve version"
        else
            echo "Container not running"
        fi
        
        echo ""
        echo "Configuration Summary:"
        echo "----------------------"
        grep -E "^(rpcuser|maxconnections|dbcache|prune)" config/bitcoin.conf 2>/dev/null || echo "Could not read configuration"
        
    } > "$info_file"
    
    log_success "System information saved"
}

# Compress backup
compress_backup() {
    log_info "Compressing backup..."
    
    cd "$BACKUP_DIR"
    tar -czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
    rm -rf "$BACKUP_NAME"
    cd - > /dev/null
    
    local backup_size=$(du -h "$BACKUP_DIR/$BACKUP_NAME.tar.gz" | cut -f1)
    log_success "Backup compressed: $BACKUP_NAME.tar.gz ($backup_size)"
}

# Clean old backups
clean_old_backups() {
    log_info "Cleaning old backups (keeping last 7)..."
    
    cd "$BACKUP_DIR"
    ls -t bitcoin_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f
    cd - > /dev/null
    
    local remaining_backups=$(ls "$BACKUP_DIR"/bitcoin_backup_*.tar.gz 2>/dev/null | wc -l)
    log_success "Cleanup completed ($remaining_backups backups remaining)"
}

# List existing backups
list_backups() {
    echo -e "${BLUE}📦 Available Backups:${NC}"
    echo ""
    
    if [[ -d "$BACKUP_DIR" ]]; then
        ls -lah "$BACKUP_DIR"/bitcoin_backup_*.tar.gz 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        
        echo ""
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo "Total backup size: $total_size"
    else
        echo "  No backups found"
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        log_error "Please specify a backup file to restore"
        list_backups
        return 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    log_warning "This will overwrite current configuration!"
    read -p "Are you sure you want to restore from $backup_file? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled"
        return 0
    fi
    
    log_info "Stopping Bitcoin node..."
    cd docker
    docker-compose down
    cd ..
    
    log_info "Restoring from backup..."
    
    # Extract backup
    local temp_dir="/tmp/bitcoin_restore_$$"
    mkdir -p "$temp_dir"
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find extracted directory
    local extracted_dir=$(find "$temp_dir" -name "bitcoin_backup_*" -type d | head -1)
    
    if [[ -z "$extracted_dir" ]]; then
        log_error "Could not find backup data in archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore configuration
    cp "$extracted_dir/bitcoin.conf" config/
    cp "$extracted_dir/bitcoin.conf.example" config/
    
    # Restore wallet data if present
    if [[ -d "$extracted_dir/wallets" ]]; then
        cp -r "$extracted_dir/wallets" data/
        log_success "Wallet data restored"
    fi
    
    # Clean up
    rm -rf "$temp_dir"
    
    log_success "Restore completed"
    log_info "Starting Bitcoin node..."
    
    cd docker
    docker-compose up -d
    cd ..
    
    log_success "Bitcoin node restarted"
}

# Main backup function
perform_backup() {
    echo ""
    log_info "🗄️  Starting Bitcoin Core backup..."
    echo ""
    
    create_backup_dir
    backup_config
    backup_wallet
    backup_system_info
    
    # Ask about chainstate backup (large and time-consuming)
    read -p "Include chainstate backup? (large file, y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        backup_chainstate
    fi
    
    compress_backup
    clean_old_backups
    
    echo ""
    log_success "🎉 Backup completed successfully!"
    echo ""
    log_info "Backup location: $BACKUP_DIR/$BACKUP_NAME.tar.gz"
    echo ""
}

# Schedule automatic backups
schedule_backups() {
    log_info "Setting up automatic daily backups..."
    
    # Create cron job
    local cron_job="0 2 * * * $(pwd)/scripts/backup.sh auto"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "scripts/backup.sh"; then
        log_warning "Backup cron job already exists"
    else
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log_success "Daily backup scheduled for 2:00 AM"
    fi
}

# Parse command line arguments
case "${1:-}" in
    "list")
        list_backups
        ;;
    "restore")
        restore_backup "$2"
        ;;
    "schedule")
        schedule_backups
        ;;
    "auto")
        # Automated backup (no prompts)
        create_backup_dir
        backup_config
        backup_system_info
        compress_backup
        clean_old_backups
        log_success "Automated backup completed: $BACKUP_NAME.tar.gz"
        ;;
    "help"|"-h"|"--help")
        echo "Bitcoin Core Backup Script"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  (no args)         - Interactive backup"
        echo "  list              - List available backups"
        echo "  restore <file>    - Restore from backup file"
        echo "  schedule          - Set up automatic daily backups"
        echo "  auto              - Automated backup (no prompts)"
        echo "  help              - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0                           # Interactive backup"
        echo "  $0 list                      # List backups"
        echo "  $0 restore backup.tar.gz     # Restore from backup"
        ;;
    "")
        perform_backup
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac