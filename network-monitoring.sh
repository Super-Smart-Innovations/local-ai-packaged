#!/bin/bash
# Network Performance Monitoring Script

MONITORING_INTERVAL=60  # seconds
LOG_FILE="network-monitoring.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

monitor_container_network() {
    echo "Container Network Performance:" >> "$LOG_FILE"

    # Get network statistics for running containers
    docker stats --no-stream --format "table {{.Name}}\t{{.NetIO}}" | while read line; do
        echo "$line" >> "$LOG_FILE"
    done

    echo "" >> "$LOG_FILE"
}

monitor_docker_networks() {
    echo "Docker Networks Status:" >> "$LOG_FILE"

    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" >> "$LOG_FILE"

    echo "" >> "$LOG_FILE"
    echo "Network Details:" >> "$LOG_FILE"

    for network in $(docker network ls --format "{{.Name}}"); do
        if [[ $network == localai* ]]; then
            echo "Network: $network" >> "$LOG_FILE"
            docker network inspect $network --format "{{.IPAM.Config}}" >> "$LOG_FILE"
            echo "Connected containers: $(docker network inspect $network --format "{{len .Containers}}")" >> "$LOG_FILE"
            echo "" >> "$LOG_FILE"
        fi
    done
}

monitor_system_network() {
    echo "System Network Statistics:" >> "$LOG_FILE"

    # Network interface statistics
    ip -s link show | head -20 >> "$LOG_FILE" 2>/dev/null || echo "ip command not available" >> "$LOG_FILE"

    echo "" >> "$LOG_FILE"
    echo "Network Connections:" >> "$LOG_FILE"
    netstat -tuln 2>/dev/null | wc -l >> "$LOG_FILE" 2>/dev/null || echo "netstat not available" >> "$LOG_FILE"

    echo "" >> "$LOG_FILE"
}

check_network_performance() {
    echo "Network Performance Tests:" >> "$LOG_FILE"

    # Test local network latency
    if command -v ping &> /dev/null; then
        echo "Local ping test:" >> "$LOG_FILE"
        ping -c 3 127.0.0.1 | tail -1 >> "$LOG_FILE" 2>/dev/null || echo "Ping test failed" >> "$LOG_FILE"
    fi

    # Test DNS resolution time
    if command -v dig &> /dev/null; then
        echo "DNS resolution time:" >> "$LOG_FILE"
        dig +stats google.com | grep "Query time" >> "$LOG_FILE" 2>/dev/null || echo "DNS test failed" >> "$LOG_FILE"
    fi

    echo "" >> "$LOG_FILE"
}

# Main monitoring loop
echo "Starting network performance monitoring..."
echo "Monitoring interval: $MONITORING_INTERVAL seconds"
echo "Log file: $LOG_FILE"

log "Network monitoring started"

while true; do
    log "=== Network Performance Report ==="

    monitor_container_network
    monitor_docker_networks
    monitor_system_network
    check_network_performance

    log "=== End Report ==="
    log ""

    sleep $MONITORING_INTERVAL
done
