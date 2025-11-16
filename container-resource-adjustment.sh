#!/bin/bash
# Container Resource Adjustment Script
# Dynamically adjusts container resource limits based on usage

CONTAINER_NAME="ubuntu-server"
ADJUSTMENT_INTERVAL=300  # 5 minutes
MEMORY_THRESHOLD=80     # Adjust if usage > 80%
CPU_THRESHOLD=75        # Adjust if usage > 75%

echo "Container Resource Adjustment Service"
echo "===================================="
echo "Monitoring container: $CONTAINER_NAME"
echo "Adjustment interval: $ADJUSTMENT_INTERVAL seconds"
echo "Memory threshold: $MEMORY_THRESHOLD%"
echo "CPU threshold: $CPU_THRESHOLD%"
echo ""

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a container-adjustments.log
}

get_container_memory_usage() {
    docker stats --no-stream --format "{{.MemPerc}}" $CONTAINER_NAME 2>/dev/null | sed 's/%//'
}

get_container_cpu_usage() {
    docker stats --no-stream --format "{{.CPUPerc}}" $CONTAINER_NAME 2>/dev/null | sed 's/%//'
}

adjust_container_memory() {
    CURRENT_MEMORY=$(docker inspect $CONTAINER_NAME --format "{{.HostConfig.Memory}}" 2>/dev/null)
    CURRENT_MEMORY_GB=$(echo "scale=2; $CURRENT_MEMORY / 1024 / 1024 / 1024" | bc 2>/dev/null)

    # Increase memory by 25%
    NEW_MEMORY=$(echo "$CURRENT_MEMORY * 1.25" | bc | cut -d'.' -f1)
    NEW_MEMORY_GB=$(echo "scale=2; $NEW_MEMORY / 1024 / 1024 / 1024" | bc 2>/dev/null)

    log "Adjusting container memory from ${CURRENT_MEMORY_GB}GB to ${NEW_MEMORY_GB}GB"

    docker update --memory $NEW_MEMORY $CONTAINER_NAME 2>/dev/null

    if [ $? -eq 0 ]; then
        log "âœ“ Container memory adjusted successfully"
    else
        log "âœ— Failed to adjust container memory"
    fi
}

adjust_container_cpu() {
    CURRENT_CPUS=$(docker inspect $CONTAINER_NAME --format "{{.HostConfig.NanoCpus}}" 2>/dev/null | awk '{print $1 / 1000000000}')

    # Increase CPU by 0.5 cores
    NEW_CPUS=$(echo "$CURRENT_CPUS + 0.5" | bc)

    log "Adjusting container CPUs from $CURRENT_CPUS to $NEW_CPUS"

    docker update --cpus $NEW_CPUS $CONTAINER_NAME 2>/dev/null

    if [ $? -eq 0 ]; then
        log "âœ“ Container CPU adjusted successfully"
    else
        log "âœ— Failed to adjust container CPU"
    fi
}

# Main adjustment loop
log "Container resource adjustment service started"

while true; do
    if docker ps --filter "name=$CONTAINER_NAME" --filter "status=running" | grep -q "$CONTAINER_NAME"; then
        MEMORY_USAGE=$(get_container_memory_usage)
        CPU_USAGE=$(get_container_cpu_usage)

        ADJUSTMENT_MADE=false

        if [ ! -z "$MEMORY_USAGE" ] && (( $(echo "$MEMORY_USAGE > $MEMORY_THRESHOLD" | bc -l) )); then
            log "High memory usage detected: $MEMORY_USAGE%"
            adjust_container_memory
            ADJUSTMENT_MADE=true
        fi

        if [ ! -z "$CPU_USAGE" ] && (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
            log "High CPU usage detected: $CPU_USAGE%"
            adjust_container_cpu
            ADJUSTMENT_MADE=true
        fi

        if [ "$ADJUSTMENT_MADE" = "false" ]; then
            log "Resource usage within normal limits"
        fi
    else
        log "Container $CONTAINER_NAME is not running"
    fi

    sleep $ADJUSTMENT_INTERVAL
done
