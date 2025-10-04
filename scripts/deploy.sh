#!/bin/bash

# Bitcoin Core Node Deployment Script
# This script builds and deploys the Bitcoin Core node

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Determine which docker-compose file to use
get_compose_file() {
    if [[ $(uname -m) == "aarch64" ]] && [[ $(uname -s) == "Linux" ]] && [[ -f /proc/device-tree/model ]]; then
        echo "docker-compose.production.yml"
    else
        echo "docker-compose.yml"
    fi
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    log_success "Docker is running"
}

# Check if required files exist
check_files() {
    local files=(
        "docker/Dockerfile"
        "docker/docker-compose.yml"
        "config/bitcoin.conf"
    )
    
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check for optional monitoring config
    if [[ ! -f "config/promtail.yml" ]]; then
        log_warning "promtail.yml not found - monitoring services will not work"
    fi
    
    log_success "All required files found"
}

# Check configuration
check_config() {
    if grep -q "PLEASE-CHANGE-THIS-SECURE-PASSWORD" config/bitcoin.conf; then
        log_warning "Please update the RPC password in config/bitcoin.conf"
        log_warning "Change 'PLEASE-CHANGE-THIS-SECURE-PASSWORD-*' to a secure password"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check disk space
check_disk_space() {
    local required_space_gb=600  # Bitcoin blockchain + some overhead
    local available_space_gb=$(df -BG ./data | awk 'NR==2{print $4}' | sed 's/G//')
    
    if [[ $available_space_gb -lt $required_space_gb ]]; then
        log_warning "Available disk space: ${available_space_gb}GB"
        log_warning "Recommended space: ${required_space_gb}GB+"
        log_warning "Consider enabling pruning in bitcoin.conf"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Sufficient disk space available: ${available_space_gb}GB"
    fi
}

# Create necessary directories
setup_directories() {
    log_info "Setting up directories..."
    
    # Ensure data directory exists and has correct permissions
    mkdir -p data logs
    
    # Check if we need to create the bitcoin data subdirectory
    if [[ ! -d "data/.bitcoin" ]]; then
        mkdir -p data/.bitcoin
    fi
    
    # Set permissions (adjust UID/GID if needed)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo chown -R 1000:1000 data logs
    fi
    
    log_success "Directories set up"
}

# Build Docker image
build_image() {
    log_info "Building Bitcoin Core Docker image..."
    log_info "This may take 30-60 minutes on Raspberry Pi 5..."
    log_warning "If you previously had a build failure, this rebuild should fix missing dependencies"
    
    cd docker
    
    # Remove any existing failed image
    docker rmi bitcoin-core:latest 2>/dev/null || true
    
    # Build with no cache to ensure clean build
    docker build \
        --no-cache \
        --tag bitcoin-core:latest \
        --build-arg BITCOIN_VERSION=26.0 \
        .
    
    if [[ $? -eq 0 ]]; then
        log_success "Docker image built successfully"
    else
        log_error "Docker build failed"
        exit 1
    fi
    
    cd ..
}

# Deploy containers
deploy_containers() {
    log_info "Deploying Bitcoin Core node..."
    
    cd docker
    
    # Check if we're on a Raspberry Pi or similar ARM64 Linux system
    if [[ $(uname -m) == "aarch64" ]] && [[ $(uname -s) == "Linux" ]] && [[ -f /proc/device-tree/model ]]; then
        log_info "Detected Raspberry Pi - using production configuration"
        docker-compose -f docker-compose.production.yml up -d
    else
        log_info "Using development/compatibility configuration"
        docker-compose up -d
    fi
    
    cd ..
    
    log_success "Bitcoin Core node deployed"
}

# Show status
show_status() {
    log_info "Container status:"
    cd docker
    
    # Determine which compose file to use
    if [[ $(uname -m) == "aarch64" ]] && [[ $(uname -s) == "Linux" ]] && [[ -f /proc/device-tree/model ]]; then
        docker-compose -f docker-compose.production.yml ps
        local compose_file="docker-compose.production.yml"
    else
        docker-compose ps
        local compose_file="docker-compose.yml"
    fi
    
    cd ..
    
    echo ""
    log_info "To view logs:"
    echo "  docker-compose -f docker/$compose_file logs -f bitcoin-node"
    echo ""
    log_info "To monitor sync progress:"
    echo "  ./scripts/monitor.sh"
    echo ""
    log_info "To check system resources:"
    echo "  htop"
}

# Main deployment function
main() {
    echo ""
    log_info "🚀 Starting Bitcoin Core Node Deployment"
    echo ""
    
    # Pre-flight checks
    check_docker
    check_files
    check_config
    check_disk_space
    
    # Setup
    setup_directories
    
    # Build and deploy
    build_image
    deploy_containers
    
    echo ""
    log_success "🎉 Bitcoin Core node deployment completed!"
    echo ""
    
    show_status
    
    echo ""
    log_warning "⏳ Initial blockchain synchronization will take several days"
    log_warning "📡 Make sure port 8333 is open for optimal P2P connectivity"
    log_warning "💾 Monitor disk usage during the sync process"
    echo ""
}

# Parse command line arguments
case "${1:-}" in
    "build")
        check_docker
        check_files
        setup_directories
        build_image
        ;;
    "up"|"start")
        check_docker
        check_files
        deploy_containers
        show_status
        ;;
    "down"|"stop")
        cd docker
        compose_file=$(get_compose_file)
        docker-compose -f "$compose_file" down
        cd ..
        log_success "Bitcoin Core node stopped"
        ;;
    "restart")
        cd docker
        compose_file=$(get_compose_file)
        docker-compose -f "$compose_file" restart
        cd ..
        log_success "Bitcoin Core node restarted"
        show_status
        ;;
    "logs")
        cd docker
        compose_file=$(get_compose_file)
        docker-compose -f "$compose_file" logs -f bitcoin-node
        cd ..
        ;;
    "status")
        show_status
        ;;
    "clean")
        log_warning "This will remove all containers and images"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd docker
            compose_file=$(get_compose_file)
            docker-compose -f "$compose_file" down --rmi all --volumes
            cd ..
            log_success "Cleanup completed"
        fi
        ;;
    "rebuild")
        log_info "Rebuilding Bitcoin Core image (fixes dependency issues)"
        check_docker
        check_files
        setup_directories
        
        # Stop existing containers
        cd docker
        compose_file=$(get_compose_file)
        docker-compose -f "$compose_file" down
        cd ..
        
        # Force rebuild
        build_image
        deploy_containers
        show_status
        ;;
    "help"|"-h"|"--help")
        echo "Bitcoin Core Node Deployment Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  - Full deployment (build + start)"
        echo "  build      - Build Docker image only"
        echo "  up/start   - Start containers"
        echo "  down/stop  - Stop containers"
        echo "  restart    - Restart containers"
        echo "  logs       - View logs"
        echo "  status     - Show status"
        echo "  rebuild    - Force rebuild (fixes dependency issues)"
        echo "  clean      - Remove containers and images"
        echo "  help       - Show this help"
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac