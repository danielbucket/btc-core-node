#!/bin/bash

# Bitcoin Core Update Script
# This script updates Bitcoin Core to the latest version

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CURRENT_VERSION="26.0"
BITCOIN_RELEASES_URL="https://api.github.com/repos/bitcoin/bitcoin/releases/latest"

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

# Check current Bitcoin Core version
check_current_version() {
    if docker ps | grep -q bitcoin-core-node; then
        local current_version=$(docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getnetworkinfo | jq -r '.subversion' | sed 's/[^0-9.]//g')
        echo "$current_version"
    else
        echo "$CURRENT_VERSION"
    fi
}

# Get latest Bitcoin Core version from GitHub
get_latest_version() {
    local latest_release=$(curl -s "$BITCOIN_RELEASES_URL")
    echo "$latest_release" | jq -r '.tag_name' | sed 's/^v//'
}

# Compare versions
version_compare() {
    local version1=$1
    local version2=$2
    
    if [[ "$version1" == "$version2" ]]; then
        return 0  # Equal
    fi
    
    local IFS=.
    local i ver1=($version1) ver2=($version2)
    
    # Fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done
    
    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            return 1  # version1 > version2
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            return 2  # version1 < version2
        fi
    done
    return 0  # Equal
}

# Backup before update
create_backup() {
    log_info "Creating backup before update..."
    ./scripts/backup.sh auto
    log_success "Backup created"
}

# Update Docker image
update_docker_image() {
    local new_version=$1
    
    log_info "Building new Docker image with Bitcoin Core $new_version..."
    
    cd docker
    
    # Update Dockerfile with new version
    sed -i.bak "s/ARG BITCOIN_VERSION=.*/ARG BITCOIN_VERSION=$new_version/" Dockerfile
    
    # Build new image
    docker build \
        --tag bitcoin-core:$new_version \
        --tag bitcoin-core:latest \
        --build-arg BITCOIN_VERSION=$new_version \
        .
    
    cd ..
    
    log_success "New Docker image built"
}

# Update containers
update_containers() {
    log_info "Updating containers..."
    
    cd docker
    
    # Stop current containers
    docker-compose down
    
    # Start with new image
    docker-compose up -d
    
    cd ..
    
    log_success "Containers updated and restarted"
}

# Verify update
verify_update() {
    local expected_version=$1
    
    log_info "Verifying update..."
    
    # Wait for container to start
    sleep 10
    
    # Check if container is running
    if ! docker ps | grep -q bitcoin-core-node; then
        log_error "Container failed to start"
        return 1
    fi
    
    # Wait for Bitcoin Core to initialize
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getnetworkinfo >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((retries++))
    done
    
    if [[ $retries -eq 30 ]]; then
        log_error "Bitcoin Core failed to start properly"
        return 1
    fi
    
    # Check version
    local actual_version=$(docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getnetworkinfo | jq -r '.subversion' | sed 's/[^0-9.]//g')
    
    if [[ "$actual_version" == "$expected_version" ]]; then
        log_success "Update verified: Bitcoin Core $actual_version"
        return 0
    else
        log_error "Version mismatch: expected $expected_version, got $actual_version"
        return 1
    fi
}

# Rollback to previous version
rollback() {
    log_warning "Rolling back to previous version..."
    
    cd docker
    
    # Restore Dockerfile
    if [[ -f Dockerfile.bak ]]; then
        mv Dockerfile.bak Dockerfile
    fi
    
    # Rebuild and restart
    docker-compose down
    docker build --tag bitcoin-core:latest .
    docker-compose up -d
    
    cd ..
    
    log_success "Rollback completed"
}

# Main update function
perform_update() {
    echo ""
    log_info "🔄 Bitcoin Core Update Process"
    echo ""
    
    # Check for internet connection
    if ! curl -s --head "$BITCOIN_RELEASES_URL" > /dev/null; then
        log_error "No internet connection available"
        exit 1
    fi
    
    # Get current and latest versions
    local current_version=$(check_current_version)
    local latest_version=$(get_latest_version)
    
    log_info "Current version: $current_version"
    log_info "Latest version: $latest_version"
    echo ""
    
    # Compare versions
    version_compare "$current_version" "$latest_version"
    local comparison=$?
    
    case $comparison in
        0)
            log_success "You are already running the latest version!"
            exit 0
            ;;
        1)
            log_warning "You are running a newer version than the latest release"
            exit 0
            ;;
        2)
            log_info "Update available: $current_version → $latest_version"
            ;;
    esac
    
    # Confirm update
    read -p "Do you want to update to Bitcoin Core $latest_version? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Update cancelled"
        exit 0
    fi
    
    # Perform update
    create_backup
    
    if update_docker_image "$latest_version"; then
        if update_containers; then
            if verify_update "$latest_version"; then
                log_success "🎉 Update completed successfully!"
                
                # Clean up old Docker images
                docker image prune -f
                
                echo ""
                log_info "Update summary:"
                echo "  Previous version: $current_version"
                echo "  New version: $latest_version"
                echo "  Backup created: $(ls -t ~/bitcoin-backups/bitcoin_backup_*.tar.gz 2>/dev/null | head -1 || echo 'None')"
                echo ""
                log_info "Monitor the node with: ./scripts/monitor.sh"
            else
                log_error "Update verification failed"
                read -p "Do you want to rollback? (Y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    rollback
                fi
                exit 1
            fi
        else
            log_error "Container update failed"
            rollback
            exit 1
        fi
    else
        log_error "Docker image build failed"
        exit 1
    fi
}

# Check for updates only
check_updates() {
    log_info "Checking for Bitcoin Core updates..."
    
    local current_version=$(check_current_version)
    local latest_version=$(get_latest_version)
    
    echo "Current version: $current_version"
    echo "Latest version: $latest_version"
    
    version_compare "$current_version" "$latest_version"
    local comparison=$?
    
    case $comparison in
        0)
            echo -e "${GREEN}✅ You are running the latest version${NC}"
            ;;
        1)
            echo -e "${YELLOW}⚠️  You are running a newer version than the latest release${NC}"
            ;;
        2)
            echo -e "${BLUE}🔄 Update available: $current_version → $latest_version${NC}"
            echo ""
            echo "Run './scripts/update.sh' to update"
            ;;
    esac
}

# Parse command line arguments
case "${1:-}" in
    "check")
        check_updates
        ;;
    "force")
        log_warning "Forcing update regardless of version"
        # Remove version check and proceed with update
        perform_update
        ;;
    "rollback")
        rollback
        ;;
    "help"|"-h"|"--help")
        echo "Bitcoin Core Update Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  - Check and perform update if available"
        echo "  check      - Check for updates without updating"
        echo "  force      - Force update regardless of version"
        echo "  rollback   - Rollback to previous version"
        echo "  help       - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0         # Interactive update"
        echo "  $0 check   # Check for updates"
        ;;
    "")
        perform_update
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac