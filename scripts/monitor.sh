#!/bin/bash

# Bitcoin Core Node Monitoring Script
# This script provides real-time monitoring of the Bitcoin node

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if bitcoin-cli is available through Docker
check_bitcoin_cli() {
    if ! docker ps | grep -q bitcoin-core-node; then
        echo -e "${RED}❌ Bitcoin Core container is not running${NC}"
        exit 1
    fi
}

# Execute bitcoin-cli command through Docker
bitcoin_cli() {
    docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin "$@"
}

# Get blockchain info
get_blockchain_info() {
    bitcoin_cli getblockchaininfo 2>/dev/null
}

# Get network info
get_network_info() {
    bitcoin_cli getnetworkinfo 2>/dev/null
}

# Get peer info
get_peer_info() {
    bitcoin_cli getpeerinfo 2>/dev/null
}

# Get memory info
get_memory_info() {
    bitcoin_cli getmemoryinfo 2>/dev/null
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc)GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc)MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=1; $bytes/1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

# Calculate sync progress
calculate_sync_progress() {
    local blockchain_info=$(get_blockchain_info)
    local current_blocks=$(echo "$blockchain_info" | jq -r '.blocks')
    local headers=$(echo "$blockchain_info" | jq -r '.headers')
    local progress=$(echo "$blockchain_info" | jq -r '.verificationprogress')
    
    local progress_percent=$(echo "scale=2; $progress * 100" | bc)
    
    echo "Current blocks: $current_blocks"
    echo "Headers: $headers"
    echo "Sync progress: ${progress_percent}%"
    
    if [[ $current_blocks -eq $headers ]]; then
        echo -e "${GREEN}✅ Fully synchronized${NC}"
        return 0
    else
        local remaining_blocks=$((headers - current_blocks))
        echo -e "${YELLOW}⏳ Syncing... ($remaining_blocks blocks remaining)${NC}"
        return 1
    fi
}

# Show system resources
show_system_resources() {
    echo -e "${BLUE}📊 System Resources:${NC}"
    
    # CPU usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "CPU Usage: ${cpu_usage}%"
    
    # Memory usage
    local mem_info=$(free -m)
    local mem_used=$(echo "$mem_info" | awk 'NR==2{printf "%.1f", $3*100/$2}')
    local mem_total=$(echo "$mem_info" | awk 'NR==2{print $2}')
    echo "Memory Usage: ${mem_used}% of ${mem_total}MB"
    
    # Disk usage for Bitcoin data
    local disk_usage=$(df -h ./data 2>/dev/null || df -h .)
    echo "Disk Usage: $(echo "$disk_usage" | awk 'NR==2{print $3 " / " $2 " (" $5 ")"}')"
    
    # Docker container stats
    echo ""
    echo -e "${BLUE}🐳 Container Resources:${NC}"
    docker stats bitcoin-core-node --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
}

# Show network status
show_network_status() {
    echo -e "${BLUE}🌐 Network Status:${NC}"
    
    local network_info=$(get_network_info)
    local connections=$(echo "$network_info" | jq -r '.connections')
    local version=$(echo "$network_info" | jq -r '.subversion')
    
    echo "Bitcoin Core version: $version"
    echo "Active connections: $connections"
    
    # Check if port 8333 is reachable
    if timeout 5 bash -c "</dev/tcp/$(hostname -I | awk '{print $1}')/8333" 2>/dev/null; then
        echo -e "${GREEN}✅ Port 8333 is open${NC}"
    else
        echo -e "${YELLOW}⚠️  Port 8333 may not be accessible from outside${NC}"
    fi
    
    # Show peer info summary
    local peer_count=$(get_peer_info | jq '. | length')
    echo "Connected peers: $peer_count"
    
    if [[ $peer_count -gt 0 ]]; then
        echo ""
        echo "Peer countries:"
        get_peer_info | jq -r '.[].addr' | cut -d':' -f1 | sort | uniq -c | head -5
    fi
}

# Show memory pool info
show_mempool_info() {
    echo -e "${BLUE}💾 Memory Pool:${NC}"
    
    local mempool_info=$(bitcoin_cli getmempoolinfo 2>/dev/null)
    local mempool_size=$(echo "$mempool_info" | jq -r '.size')
    local mempool_bytes=$(echo "$mempool_info" | jq -r '.bytes')
    
    echo "Transactions in mempool: $mempool_size"
    echo "Mempool size: $(format_bytes $mempool_bytes)"
}

# Main monitoring function
show_status() {
    clear
    echo -e "${CYAN}🪙 Bitcoin Core Node Status${NC}"
    echo "$(date)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Check if node is running
    if ! docker ps | grep -q bitcoin-core-node; then
        echo -e "${RED}❌ Bitcoin Core container is not running${NC}"
        echo ""
        echo "To start the node: ./scripts/deploy.sh start"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Bitcoin Core node is running${NC}"
    echo ""
    
    # Blockchain sync status
    echo -e "${BLUE}⛓️  Blockchain Status:${NC}"
    calculate_sync_progress
    echo ""
    
    # Network status
    show_network_status
    echo ""
    
    # Memory pool
    show_mempool_info
    echo ""
    
    # System resources
    show_system_resources
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Commands:"
    echo "  ./scripts/monitor.sh logs    - View real-time logs"
    echo "  ./scripts/monitor.sh cli     - Interactive Bitcoin CLI"
    echo "  ./scripts/deploy.sh status   - Container status"
    echo "  ./scripts/backup.sh          - Backup configuration"
}

# Show real-time logs
show_logs() {
    echo "📜 Showing Bitcoin Core logs (Ctrl+C to exit)..."
    cd docker
    docker-compose logs -f bitcoin-node
    cd ..
}

# Interactive CLI
interactive_cli() {
    echo "🖥️  Bitcoin Core Interactive CLI"
    echo "Type 'help' for available commands, 'exit' to quit"
    echo ""
    
    while true; do
        read -p "bitcoin-cli> " command
        
        if [[ "$command" == "exit" ]]; then
            break
        fi
        
        if [[ -z "$command" ]]; then
            continue
        fi
        
        bitcoin_cli $command || echo "Command failed or invalid"
        echo ""
    done
}

# Watch mode (continuous monitoring)
watch_mode() {
    echo "🔄 Starting continuous monitoring (Ctrl+C to exit)..."
    echo ""
    
    while true; do
        show_status
        echo "Refreshing in 30 seconds..."
        sleep 30
    done
}

# Main script logic
check_bitcoin_cli

case "${1:-}" in
    "logs")
        show_logs
        ;;
    "cli")
        interactive_cli
        ;;
    "watch")
        watch_mode
        ;;
    "sync")
        echo -e "${BLUE}⛓️  Sync Status:${NC}"
        calculate_sync_progress
        ;;
    "peers")
        echo -e "${BLUE}👥 Peer Information:${NC}"
        get_peer_info | jq -r '.[] | "\(.addr) - \(.subver) - \(.conntime)s"' | head -10
        ;;
    "help")
        echo "Bitcoin Core Node Monitoring Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)  - Show current status"
        echo "  logs       - View real-time logs"
        echo "  cli        - Interactive Bitcoin CLI"
        echo "  watch      - Continuous monitoring"
        echo "  sync       - Show sync progress only"
        echo "  peers      - Show peer information"
        echo "  help       - Show this help"
        ;;
    "")
        show_status
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac