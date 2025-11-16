#!/bin/bash
# Container Monitoring Script for Nested Architecture
# Monitors both host container and nested services

CONTAINER_NAME="ubuntu-server"
MONITORING_INTERVAL=30

echo "Container Performance Monitoring"
echo "==============================="
echo "Monitoring container: $CONTAINER_NAME"
echo "Update interval: $MONITORING_INTERVAL seconds"
echo ""

# Function to get container resource usage
get_container_stats() {
    echo "=== Container Resource Usage ==="
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $CONTAINER_NAME 2>/dev/null || echo "Container not running"
    echo ""
}

# Function to get nested services stats
get_nested_services_stats() {
    echo "=== Nested Services Resource Usage ==="
    if docker exec $CONTAINER_NAME docker ps -q 2>/dev/null | grep -q .; then
        docker exec $CONTAINER_NAME docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "Unable to get nested service stats"
    else
        echo "No nested services running"
    fi
    echo ""
}

# Function to check container health
check_container_health() {
    echo "=== Container Health Check ==="
    HEALTH_STATUS=$(docker inspect $CONTAINER_NAME --format "{{.State.Health.Status}}" 2>/dev/null || echo "unknown")

    if [ "$HEALTH_STATUS" = "healthy" ]; then
        echo "âœ“ Container health: HEALTHY"
    elif [ "$HEALTH_STATUS" = "unhealthy" ]; then
        echo "âœ— Container health: UNHEALTHY"
    else
        echo "? Container health: $HEALTH_STATUS"
    fi

    # Check container resource limits
    CONTAINER_MEMORY=$(docker inspect $CONTAINER_NAME --format "{{.HostConfig.Memory}}" 2>/dev/null | awk '{print $1 / 1024 / 1024 / 1024 "GB"}')
    CONTAINER_CPUS=$(docker inspect $CONTAINER_NAME --format "{{.HostConfig.NanoCpus}}" 2>/dev/null | awk '{print $1 / 1000000000}')

    echo "Container limits: ${CONTAINER_MEMORY} memory, ${CONTAINER_CPUS} CPUs"
    echo ""
}

# Function to check nested services health
check_nested_services_health() {
    echo "=== Nested Services Health Check ==="
    RUNNING_SERVICES=$(docker exec $CONTAINER_NAME docker ps --filter "status=running" --format "{{.Names}}" 2>/dev/null | wc -l)
    TOTAL_SERVICES=$(docker exec $CONTAINER_NAME docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l)

    echo "Running services: $RUNNING_SERVICES / $TOTAL_SERVICES"

    if [ "$RUNNING_SERVICES" -lt "$TOTAL_SERVICES" ]; then
        echo "âš  Some services are not running:"
        docker exec $CONTAINER_NAME docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "Unable to list stopped services"
    fi
    echo ""
}

# Main monitoring loop
log_file="container-monitoring-20251109-103605.log"
echo "Logging to: $log_file"
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[] Monitoring cycle started" >> "$log_file"

    get_container_stats | tee -a "$log_file"
    get_nested_services_stats | tee -a "$log_file"
    check_container_health | tee -a "$log_file"
    check_nested_services_health | tee -a "$log_file"

    echo "Monitoring cycle complete. Waiting $MONITORING_INTERVAL seconds..." | tee -a "$log_file"
    echo "----------------------------------------" >> "$log_file"
    sleep $MONITORING_INTERVAL
done
