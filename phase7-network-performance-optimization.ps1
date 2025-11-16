# Phase 7: Network Performance Optimization Settings
# This script configures network performance optimizations for Docker and services

Write-Host "Creating network performance optimization settings..." -ForegroundColor Green

# Create Docker network configuration
@"
# Docker Network Performance Configuration
# Optimized for high-performance inter-container communication

networks:
  localai-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: localai-br0
    ipam:
      config:
        - subnet: 172.20.0.0/16
    options:
      # Enable IP forwarding for better performance
      com.docker.network.bridge.enable_ip_forward: "true"
      # Disable ICMP echo to reduce network overhead
      com.docker.network.bridge.enable_icc: "true"
      # MTU optimization for jumbo frames (if supported)
      com.docker.network.driver.mtu: "1500"
      # DNS configuration for faster resolution
      com.docker.network.bridge.dns: "8.8.8.8,1.1.1.1"

  # Separate network for database traffic
  database-network:
    driver: bridge
    internal: true  # Isolated network for security
    driver_opts:
      com.docker.network.bridge.name: localai-db-br0
    ipam:
      config:
        - subnet: 172.21.0.0/16
    options:
      com.docker.network.bridge.enable_ip_forward: "false"
      com.docker.network.bridge.enable_icc: "true"
      com.docker.network.driver.mtu: "9000"  # Jumbo frames for DB traffic

  # High-performance network for AI workloads
  ai-network:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: localai-ai-br0
    ipam:
      config:
        - subnet: 172.22.0.0/16
    options:
      com.docker.network.bridge.enable_ip_forward: "true"
      com.docker.network.bridge.enable_icc: "true"
      com.docker.network.driver.mtu: "9000"  # Jumbo frames for AI data
"@ | Out-File -FilePath "docker-networks.yml" -Encoding UTF8

# Create network performance tuning script
@"
#!/bin/bash
# Network Performance Tuning Script for Docker and System

echo "Optimizing network performance settings..."

# System-level network optimizations
echo "Applying system-level network optimizations..."

# Increase network buffer sizes
sudo sysctl -w net.core.rmem_max=26214400 2>/dev/null || echo "Cannot set rmem_max (requires root)"
sudo sysctl -w net.core.wmem_max=26214400 2>/dev/null || echo "Cannot set wmem_max (requires root)"
sudo sysctl -w net.core.rmem_default=26214400 2>/dev/null || echo "Cannot set rmem_default (requires root)"
sudo sysctl -w net.core.wmem_default=26214400 2>/dev/null || echo "Cannot set wmem_default (requires root)"

# TCP optimizations
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 26214400" 2>/dev/null || echo "Cannot set tcp_rmem"
sudo sysctl -w net.ipv4.tcp_wmem="4096 16384 26214400" 2>/dev/null || echo "Cannot set tcp_wmem"
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || echo "Cannot set congestion control (BBR not available)"

# Enable TCP fast open
sudo sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || echo "Cannot enable TCP fast open"

# Optimize connection tracking
sudo sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=86400 2>/dev/null || echo "Cannot set conntrack timeout"

# Docker-specific network optimizations
echo "Applying Docker network optimizations..."

# Create optimized networks if they don't exist
docker network ls | grep -q "localai-network" || docker network create --driver bridge \
  --opt "com.docker.network.bridge.name=localai-br0" \
  --opt "com.docker.network.bridge.enable_ip_forward=true" \
  --opt "com.docker.network.bridge.enable_icc=true" \
  --opt "com.docker.network.driver.mtu=1500" \
  --subnet=172.20.0.0/16 \
  localai-network

docker network ls | grep -q "database-network" || docker network create --driver bridge \
  --internal \
  --opt "com.docker.network.bridge.name=localai-db-br0" \
  --opt "com.docker.network.bridge.enable_ip_forward=false" \
  --opt "com.docker.network.bridge.enable_icc=true" \
  --opt "com.docker.network.driver.mtu=9000" \
  --subnet=172.21.0.0/16 \
  database-network

docker network ls | grep -q "ai-network" || docker network create --driver bridge \
  --opt "com.docker.network.bridge.name=localai-ai-br0" \
  --opt "com.docker.network.bridge.enable_ip_forward=true" \
  --opt "com.docker.network.bridge.enable_icc=true" \
  --opt "com.docker.network.driver.mtu=9000" \
  --subnet=172.22.0.0/16 \
  ai-network

# Configure iptables rules for better performance (requires root)
echo "Configuring iptables optimizations..."

# Allow established connections (performance optimization)
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || echo "Cannot configure iptables (requires root)"

# Rate limiting for DoS protection
sudo iptables -A INPUT -p tcp --dport 80 -m limit --limit 100/minute --limit-burst 200 -j ACCEPT 2>/dev/null || echo "Cannot configure rate limiting"
sudo iptables -A INPUT -p tcp --dport 443 -m limit --limit 100/minute --limit-burst 200 -j ACCEPT 2>/dev/null || echo "Cannot configure rate limiting"

echo "Network performance optimizations applied."
echo ""
echo "Applied optimizations:"
echo "- Increased network buffer sizes (25MB)"
echo "- Enabled BBR congestion control"
echo "- Enabled TCP fast open"
echo "- Optimized connection tracking timeouts"
echo "- Created performance-optimized Docker networks"
echo "- Configured iptables rules for better throughput"
echo ""
echo "Note: Some optimizations require root privileges and may not apply in all environments."
"@ | Out-File -FilePath "network-performance-tuning.sh" -Encoding UTF8

# Create network monitoring script
@"
#!/bin/bash
# Network Performance Monitoring Script

MONITORING_INTERVAL=60  # seconds
LOG_FILE="network-monitoring.log"

log() {
    echo "[`$(date +'%Y-%m-%d %H:%M:%S')`] `$1`" >> "`$LOG_FILE`"
}

monitor_container_network() {
    echo "Container Network Performance:" >> "`$LOG_FILE`"

    # Get network statistics for running containers
    docker stats --no-stream --format "table {{.Name}}\t{{.NetIO}}" | while read line; do
        echo "`$line`" >> "`$LOG_FILE`"
    done

    echo "" >> "`$LOG_FILE`"
}

monitor_docker_networks() {
    echo "Docker Networks Status:" >> "`$LOG_FILE`"

    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" >> "`$LOG_FILE`"

    echo "" >> "`$LOG_FILE`"
    echo "Network Details:" >> "`$LOG_FILE`"

    for network in `$(docker network ls --format "{{.Name}}")`; do
        if [[ `$network` == localai* ]]; then
            echo "Network: `$network`" >> "`$LOG_FILE`"
            docker network inspect `$network` --format "{{.IPAM.Config}}" >> "`$LOG_FILE`"
            echo "Connected containers: `$(docker network inspect `$network` --format "{{len .Containers}}")`" >> "`$LOG_FILE`"
            echo "" >> "`$LOG_FILE`"
        fi
    done
}

monitor_system_network() {
    echo "System Network Statistics:" >> "`$LOG_FILE`"

    # Network interface statistics
    ip -s link show | head -20 >> "`$LOG_FILE`" 2>/dev/null || echo "ip command not available" >> "`$LOG_FILE`"

    echo "" >> "`$LOG_FILE`"
    echo "Network Connections:" >> "`$LOG_FILE`"
    netstat -tuln 2>/dev/null | wc -l >> "`$LOG_FILE`" 2>/dev/null || echo "netstat not available" >> "`$LOG_FILE`"

    echo "" >> "`$LOG_FILE`"
}

check_network_performance() {
    echo "Network Performance Tests:" >> "`$LOG_FILE`"

    # Test local network latency
    if command -v ping &> /dev/null; then
        echo "Local ping test:" >> "`$LOG_FILE`"
        ping -c 3 127.0.0.1 | tail -1 >> "`$LOG_FILE`" 2>/dev/null || echo "Ping test failed" >> "`$LOG_FILE`"
    fi

    # Test DNS resolution time
    if command -v dig &> /dev/null; then
        echo "DNS resolution time:" >> "`$LOG_FILE`"
        dig +stats google.com | grep "Query time" >> "`$LOG_FILE`" 2>/dev/null || echo "DNS test failed" >> "`$LOG_FILE`"
    fi

    echo "" >> "`$LOG_FILE`"
}

# Main monitoring loop
echo "Starting network performance monitoring..."
echo "Monitoring interval: `$MONITORING_INTERVAL` seconds"
echo "Log file: `$LOG_FILE`"

log "Network monitoring started"

while true; do
    log "=== Network Performance Report ==="

    monitor_container_network
    monitor_docker_networks
    monitor_system_network
    check_network_performance

    log "=== End Report ==="
    log ""

    sleep `$MONITORING_INTERVAL`
done
"@ | Out-File -FilePath "network-monitoring.sh" -Encoding UTF8

# Create inter-container communication optimization
@"
# Inter-Container Communication Optimization
# Configuration for optimal service-to-service communication

# DNS optimization for Docker networks
services:
  # Example service configuration with network optimizations
  n8n:
    networks:
      localai-network:
        aliases:
          - n8n.local
    dns:
      - 8.8.8.8
      - 1.1.1.1
    dns_search:
      - localai.local
    dns_options:
      - timeout:2
      - attempts:3

  open-webui:
    networks:
      localai-network:
        aliases:
          - openwebui.local
    dns:
      - 8.8.8.8
      - 1.1.1.1
    dns_search:
      - localai.local

  ollama:
    networks:
      ai-network:
        aliases:
          - ollama.local
      localai-network:
        aliases:
          - ollama.api.local
    dns:
      - 8.8.8.8
      - 1.1.1.1

  postgres:
    networks:
      database-network:
        aliases:
          - postgres.local
      localai-network:
        aliases:
          - db.local
    dns:
      - 8.8.8.8
      - 1.1.1.1

  redis:
    networks:
      localai-network:
        aliases:
          - redis.local
          - cache.local
    dns:
      - 8.8.8.8
      - 1.1.1.1

# Network connectivity matrix (for reference)
# This shows which services need to communicate with each other
#
# Service       -> n8n | open-webui | ollama | postgres | redis | qdrant | neo4j | caddy
# n8n           ->  -  |     ✓      |   ✓    |    ✓     |   ✓   |   ✓    |   ✓   |   ✓
# open-webui    ->  ✓  |     -      |   ✓    |    -     |   -   |   ✓    |   -   |   ✓
# ollama        ->  ✓  |     ✓      |   -    |    -     |   -   |   -    |   -   |   ✓
# postgres      ->  ✓  |     -      |   -    |    -     |   -   |   -    |   ✓   |   -
# redis         ->  ✓  |     -      |   -    |    -     |   -   |   -    |   -   |   -
# qdrant        ->  ✓  |     ✓      |   -    |    -     |   -   |   -    |   -   |   ✓
# neo4j         ->  ✓  |     -      |   -    |    ✓     |   -    |   -    |   -   |   ✓
# caddy         ->  ✓  |     ✓      |   ✓    |    -     |   -   |   ✓    |   ✓   |   -
"@ | Out-File -FilePath "inter-container-optimization.yml" -Encoding UTF8

# Create network troubleshooting script
@"
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

for service in "`${SERVICES[@]}"; do
    NAME=`$(echo `$service` | cut -d':' -f1)`
    PORT=`$(echo `$service` | cut -d':' -f2)`

    if docker ps --filter "name=`$NAME`" --filter "status=running" | grep -q "`$NAME`"; then
        echo "Testing `$NAME` on port `$PORT`..."

        # Test port accessibility
        if docker exec `$NAME` nc -z localhost `$PORT` 2>/dev/null; then
            echo "✓ `$NAME` is listening on port `$PORT`"
        else
            echo "✗ `$NAME` is not responding on port `$PORT`"
        fi
    else
        echo "⚠ `$NAME` is not running"
    fi
done

echo ""
echo "3. DNS resolution test..."
docker run --rm --network localai-network alpine nslookup n8n 2>/dev/null || echo "DNS resolution test failed"

echo ""
echo "4. Network performance test..."

# Test network latency between containers
START_TIME=`$(date +%s%N)`
docker exec n8n ping -c 1 postgres  > /dev/null 2>&1
END_TIME=`$(date +%s%N)`

if [ "`$START_TIME`" != "N/A" ] && [ "`$END_TIME`" != "N/A" ]; then
    LATENCY=`$(echo "scale=2; (`$END_TIME` - `$START_TIME`) / 1000000" | bc 2>/dev/null)`
    echo "Inter-container latency: `$LATENCY`ms"
else
    echo "Could not measure inter-container latency"
fi

echo ""
echo "5. Firewall and routing check..."
echo "Current iptables rules (first 10):"
sudo iptables -L | head -10 2>/dev/null || echo "Cannot access iptables (requires root)"

echo ""
echo "Troubleshooting complete. Check the results above for issues."
"@ | Out-File -FilePath "network-troubleshooting.sh" -Encoding UTF8

Write-Host "Network performance optimization settings created." -ForegroundColor Green
Write-Host ""
Write-Host "Files created:" -ForegroundColor Cyan
Write-Host "- docker-networks.yml: Optimized Docker network configurations"
Write-Host "- network-performance-tuning.sh: System and Docker network optimizations"
Write-Host "- network-monitoring.sh: Comprehensive network performance monitoring"
Write-Host "- inter-container-optimization.yml: Service communication optimization"
Write-Host "- network-troubleshooting.sh: Network issue diagnosis tools"
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "1. Run './network-performance-tuning.sh' to apply optimizations"
Write-Host "2. Include docker-networks.yml in your docker-compose.yml"
Write-Host "3. Run './network-monitoring.sh' for continuous network monitoring"
Write-Host "4. Use './network-troubleshooting.sh' to diagnose network issues"
Write-Host ""
Write-Host "Network optimizations applied:" -ForegroundColor Yellow
Write-Host "- Jumbo frames (MTU 9000) for high-throughput networks"
Write-Host "- Separate networks for security and performance isolation"
Write-Host "- Optimized DNS configuration for faster resolution"
Write-Host "- TCP buffer size increases for better throughput"
Write-Host "- BBR congestion control for improved performance"