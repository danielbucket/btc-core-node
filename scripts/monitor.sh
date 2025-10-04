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
    echo "🔍 Checking Bitcoin Core container status..."
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker command not found${NC}"
        echo "Please ensure Docker is installed and accessible"
        exit 1
    fi
    
    echo "📋 Listing running containers..."
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    if ! docker ps | grep -q bitcoin-core-node; then
        echo -e "${RED}❌ Bitcoin Core container 'bitcoin-core-node' is not running${NC}"
        echo ""
        echo "Available containers:"
        docker ps --format "{{.Names}}" | head -10
        echo ""
        echo "To start the node: ./scripts/deploy.sh start"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Bitcoin Core container is running${NC}"
    echo ""
    
    # Check if Bitcoin Core is ready to accept commands
    echo "🔗 Testing Bitcoin CLI connection..."
    local retries=0
    while [[ $retries -lt 3 ]]; do
        echo "   Attempt $((retries + 1))/3..."
        if docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Bitcoin CLI is responding${NC}"
            echo ""
            return 0
        fi
        
        # Show what the error actually is
        echo "   Error details:"
        docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockchaininfo 2>&1 | head -3 | sed 's/^/   /'
        echo ""
        
        echo "⏳ Bitcoin Core may still be initializing, waiting..."
        sleep 3
        ((retries++))
    done
    
    echo -e "${YELLOW}⚠️  Bitcoin Core is not responding to CLI commands${NC}"
    echo "This could mean:"
    echo "  - Bitcoin Core is still starting up (can take 5-10 minutes)"
    echo "  - Configuration issue"
    echo "  - Bitcoin Core crashed during startup"
    echo ""
    echo "Check the logs with: cd docker && docker-compose logs bitcoin-node"
    echo ""
    return 1
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
    
    # Handle invalid input
    if [[ -z "$bytes" ]] || [[ "$bytes" == "null" ]] || ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0B"
        return
    fi
    
    if command -v bc >/dev/null; then
        if [[ $bytes -ge 1073741824 ]]; then
            echo "$(echo "scale=2; $bytes/1073741824" | bc)GB"
        elif [[ $bytes -ge 1048576 ]]; then
            echo "$(echo "scale=2; $bytes/1048576" | bc)MB"
        elif [[ $bytes -ge 1024 ]]; then
            echo "$(echo "scale=1; $bytes/1024" | bc)KB"
        else
            echo "${bytes}B"
        fi
    else
        # Fallback without bc
        if [[ $bytes -ge 1073741824 ]]; then
            echo "$((bytes / 1073741824))GB"
        elif [[ $bytes -ge 1048576 ]]; then
            echo "$((bytes / 1048576))MB"
        elif [[ $bytes -ge 1024 ]]; then
            echo "$((bytes / 1024))KB"
        else
            echo "${bytes}B"
        fi
    fi
}

# Calculate sync progress
calculate_sync_progress() {
    local blockchain_info=$(get_blockchain_info)
    if [[ $? -ne 0 || -z "$blockchain_info" ]]; then
        echo "❌ Unable to retrieve blockchain information (node may be starting)"
        return 1
    fi
    
    local current_blocks=$(echo "$blockchain_info" | jq -r '.blocks // 0' 2>/dev/null || echo "0")
    local headers=$(echo "$blockchain_info" | jq -r '.headers // 0' 2>/dev/null || echo "0")
    local progress=$(echo "$blockchain_info" | jq -r '.verificationprogress // 0' 2>/dev/null || echo "0")
    
    # Validate that we got reasonable values
    if [[ "$current_blocks" == "0" ]] || [[ "$headers" == "0" ]]; then
        echo "⏳ Node is starting up, blockchain info not yet available"
        return 1
    fi
    
    local progress_percent="0"
    if command -v bc >/dev/null && [[ "$progress" != "0" ]]; then
        progress_percent=$(echo "scale=2; $progress * 100" | bc 2>/dev/null || echo "0")
    fi
    
    echo "Current blocks: $current_blocks"
    echo "Headers: $headers"
    echo "Sync progress: ${progress_percent}%"
    
    if [[ $current_blocks -eq $headers ]] && [[ $current_blocks -gt 0 ]]; then
        echo -e "${GREEN}✅ Fully synchronized${NC}"
        return 0
    else
        local remaining_blocks=$((headers - current_blocks))
        if [[ $remaining_blocks -gt 0 ]]; then
            echo -e "${YELLOW}⏳ Syncing... ($remaining_blocks blocks remaining)${NC}"
        else
            echo -e "${YELLOW}⏳ Syncing... (progress updating)${NC}"
        fi
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
    if [[ $? -eq 0 && -n "$network_info" ]]; then
        local connections=$(echo "$network_info" | jq -r '.connections // "Unknown"' 2>/dev/null || echo "Unknown")
        local version=$(echo "$network_info" | jq -r '.subversion // "Unknown"' 2>/dev/null || echo "Unknown")
        
        echo "Bitcoin Core version: $version"
        echo "Active connections: $connections"
    else
        echo "❌ Unable to retrieve network information (node may be starting)"
        return 1
    fi
    
    # Check if port 8333 is reachable (improved method)
    local port_check=false
    
    # Method 1: Check if Bitcoin is listening on 8333
    if docker exec bitcoin-core-node ss -tuln 2>/dev/null | grep -q ":8333"; then
        port_check=true
    fi
    
    # Method 2: Check with netstat if available
    if [[ $port_check == false ]] && command -v netstat >/dev/null; then
        if netstat -tuln 2>/dev/null | grep -q ":8333"; then
            port_check=true
        fi
    fi
    
    if [[ $port_check == true ]]; then
        echo -e "${GREEN}✅ Port 8333 is listening${NC}"
    else
        echo -e "${YELLOW}⚠️  Port 8333 may not be accessible from outside${NC}"
        echo "   - Check firewall settings"
        echo "   - Ensure port forwarding is configured"
    fi
    
    # Show peer info summary
    local peer_info=$(get_peer_info)
    if [[ $? -eq 0 && -n "$peer_info" ]]; then
        local peer_count=$(echo "$peer_info" | jq '. | length' 2>/dev/null || echo "0")
        echo "Connected peers: $peer_count"
        
        if [[ $peer_count -gt 0 ]]; then
            echo ""
            echo "Top peer countries:"
            echo "$peer_info" | jq -r '.[].addr' 2>/dev/null | cut -d':' -f1 | sort | uniq -c | sort -nr | head -5 2>/dev/null || echo "   Unable to parse peer locations"
        fi
    else
        echo "Connected peers: Unknown (retrieving...)"
    fi
}

# Show memory pool info
show_mempool_info() {
    echo -e "${BLUE}💾 Memory Pool:${NC}"
    
    local mempool_info=$(bitcoin_cli getmempoolinfo 2>/dev/null)
    if [[ $? -eq 0 && -n "$mempool_info" ]]; then
        local mempool_size=$(echo "$mempool_info" | jq -r '.size // 0' 2>/dev/null || echo "0")
        local mempool_bytes=$(echo "$mempool_info" | jq -r '.bytes // 0' 2>/dev/null || echo "0")
        
        echo "Transactions in mempool: $mempool_size"
        echo "Mempool size: $(format_bytes $mempool_bytes)"
    else
        echo "❌ Unable to retrieve mempool information (node may be starting)"
    fi
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
    "debug")
        echo "🐛 Debug Mode - Verbose Bitcoin Core Status"
        echo "=========================================="
        echo ""
        
        echo "1. Container Status:"
        docker ps | grep bitcoin || echo "No bitcoin containers found"
        echo ""
        
        echo "2. Container Resource Usage:"
        docker stats bitcoin-core-node --no-stream 2>/dev/null || echo "Cannot get stats"
        echo ""
        
        echo "3. Recent Container Logs (last 20 lines):"
        docker logs bitcoin-core-node --tail=20 2>/dev/null || echo "Cannot get logs"
        echo ""
        
        echo "4. Bitcoin Core Process Status:"
        docker exec bitcoin-core-node ps aux 2>/dev/null | grep bitcoin || echo "Cannot check processes"
        echo ""
        
        echo "5. Data Directory Contents:"
        docker exec bitcoin-core-node ls -la /home/bitcoin/.bitcoin/ 2>/dev/null || echo "Cannot list data directory"
        echo ""
        
        echo "6. Bitcoin CLI Test:"
        docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin help 2>&1 | head -5
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
        echo "  debug      - Verbose debug information"
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