#!/bin/bash
# Automated Resource Scaling Script
# Adjusts resource limits based on current usage and performance metrics

LOG_FILE="resource-scaling.log"
THRESHOLD_MEMORY=80  # Scale up if memory usage > 80%
THRESHOLD_CPU=70     # Scale up if CPU usage > 70%

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

get_container_memory_usage() {
    docker stats --no-stream --format "{{.Name}}:{{.MemPerc}}" | grep "^$1:" | cut -d':' -f2 | sed 's/%//'
}

get_container_cpu_usage() {
    docker stats --no-stream --format "{{.Name}}:{{.CPUPerc}}" | grep "^$1:" | cut -d':' -f2 | sed 's/%//'
}

scale_service() {
    SERVICE_NAME=$1
    CURRENT_MEMORY=$(get_container_memory_usage $SERVICE_NAME)
    CURRENT_CPU=$(get_container_cpu_usage $SERVICE_NAME)

    if (( $(echo "$CURRENT_MEMORY > $THRESHOLD_MEMORY" | bc -l) )); then
        log "High memory usage detected for $SERVICE_NAME: $CURRENT_MEMORY%"
        # Increase memory limit by 25%
        docker update --memory +256m $SERVICE_NAME 2>/dev/null || log "Failed to scale memory for $SERVICE_NAME"
    fi

    if (( $(echo "$CURRENT_CPU > $THRESHOLD_CPU" | bc -l) )); then
        log "High CPU usage detected for $SERVICE_NAME: $CURRENT_CPU%"
        # Increase CPU limit by 0.5 cores
        docker update --cpus +0.5 $SERVICE_NAME 2>/dev/null || log "Failed to scale CPU for $SERVICE_NAME"
    fi
}

log "Starting automated resource scaling check"

# Check and scale critical services
SERVICES=("ollama" "n8n" "postgres" "open-webui")

for service in "${SERVICES[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^$service$"; then
        scale_service $service
    else
        log "Service $service not running, skipping scaling check"
    fi
done

log "Resource scaling check completed"
