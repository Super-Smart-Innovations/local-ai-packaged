#!/bin/bash
# Network Troubleshooting Script for Docker Services

echo "Network Troubleshooting for Docker Services"
echo "==========================================="

# Check Docker network connectivity
echo "1. Checking Docker networks..."
docker network ls

echo ""
echo "2. Testing inter-container connectivity..."

# Test basic connectivity
SERVICES=("n8n:5678" "open-webui:8080" "postgres:5432" "redis:6379")

for service in "${SERVICES[@]}"; do
    NAME=$(echo $service | cut -d':' -f1)
    PORT=$(echo $service | cut -d':' -f2)

    if docker ps --filter "name=$NAME" --filter "status=running" | grep -q "$NAME"; then
        echo "Testing $NAME on port $PORT..."

        # Test port accessibility
        if docker exec $NAME nc -z localhost $PORT 2>/dev/null; then
            echo "âœ“ $NAME is listening on port $PORT"
        else
            echo "âœ— $NAME is not responding on port $PORT"
        fi
    else
        echo "âš  $NAME is not running"
    fi
done

echo ""
echo "3. DNS resolution test..."
docker run --rm --network localai-network alpine nslookup n8n 2>/dev/null || echo "DNS resolution test failed"

echo ""
echo "4. Network performance test..."

# Test network latency between containers
START_TIME=$(date +%s%N)
docker exec n8n ping -c 1 postgres  > /dev/null 2>&1
END_TIME=$(date +%s%N)

if [ "$START_TIME" != "N/A" ] && [ "$END_TIME" != "N/A" ]; then
    LATENCY=$(echo "scale=2; ($END_TIME - $START_TIME) / 1000000" | bc 2>/dev/null)
    echo "Inter-container latency: $LATENCYms"
else
    echo "Could not measure inter-container latency"
fi

echo ""
echo "5. Firewall and routing check..."
echo "Current iptables rules (first 10):"
sudo iptables -L | head -10 2>/dev/null || echo "Cannot access iptables (requires root)"

echo ""
echo "Troubleshooting complete. Check the results above for issues."
