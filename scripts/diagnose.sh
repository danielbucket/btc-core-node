#!/bin/bash

# Quick Bitcoin Core Diagnostic Script
# Use this when the monitor script isn't working

echo "🔍 Bitcoin Core Quick Diagnostics"
echo "================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "docker/docker-compose.yml" ]]; then
    echo "❌ Please run this from the raspiservers project directory"
    exit 1
fi

echo "1. 📦 Docker Status:"
if command -v docker >/dev/null 2>&1; then
    echo "   ✅ Docker is available"
    docker --version
else
    echo "   ❌ Docker not found"
    exit 1
fi
echo ""

echo "2. 🐳 Container Status:"
containers=$(docker ps --format "{{.Names}}" | grep -E "(bitcoin|btc)" || echo "none")
if [[ "$containers" != "none" ]]; then
    echo "   Bitcoin-related containers running:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(bitcoin|btc|NAME)"
else
    echo "   ❌ No Bitcoin containers running"
    echo "   Available containers:"
    docker ps --format "{{.Names}}" | head -5
fi
echo ""

echo "3. 📊 Container Resources (if running):"
if docker ps | grep -q bitcoin-core-node; then
    docker stats bitcoin-core-node --no-stream 2>/dev/null || echo "   Cannot get stats"
else
    echo "   Container not running"
fi
echo ""

echo "4. 📝 Recent Logs (last 10 lines):"
if docker ps | grep -q bitcoin-core-node; then
    echo "   Last 10 log entries:"
    docker logs bitcoin-core-node --tail=10 2>/dev/null | sed 's/^/   /' || echo "   Cannot retrieve logs"
else
    echo "   Container not running - checking compose logs..."
    cd docker 2>/dev/null && docker-compose logs --tail=10 bitcoin-node 2>/dev/null | sed 's/^/   /' || echo "   Cannot retrieve compose logs"
fi
echo ""

echo "5. 🔧 Quick Tests:"
if docker ps | grep -q bitcoin-core-node; then
    echo "   Testing Bitcoin CLI connection..."
    if docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin help >/dev/null 2>&1; then
        echo "   ✅ Bitcoin CLI is responsive"
        
        # Try to get basic info
        block_count=$(docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getblockcount 2>/dev/null || echo "unknown")
        echo "   Current block count: $block_count"
        
        connections=$(docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin getconnectioncount 2>/dev/null || echo "unknown")
        echo "   Active connections: $connections"
    else
        echo "   ❌ Bitcoin CLI not responding"
        echo "   Error details:"
        docker exec bitcoin-core-node bitcoin-cli -datadir=/home/bitcoin/.bitcoin help 2>&1 | head -3 | sed 's/^/      /'
    fi
else
    echo "   Cannot test - container not running"
fi
echo ""

echo "6. 💡 Next Steps:"
if docker ps | grep -q bitcoin-core-node; then
    echo "   ✅ Container is running"
    echo "   📊 Try: ./scripts/monitor.sh debug"
    echo "   📝 View logs: cd docker && docker-compose logs -f bitcoin-node"
    echo "   🔄 If stuck, restart: ./scripts/deploy.sh restart"
else
    echo "   🚀 Start the node: ./scripts/deploy.sh start"
    echo "   📋 Check deployment: ./scripts/deploy.sh status"
fi
echo ""

echo "🏁 Diagnostic complete!"