# Phase 7: Container Resource Optimization for Nested Ubuntu Architecture
# This script optimizes resource allocation for services running inside the Ubuntu container

Write-Host "Creating container resource optimization for nested Ubuntu architecture..." -ForegroundColor Green

# Create container-specific resource allocation script
@"
#!/bin/bash
# Container Resource Optimization Script
# Optimizes resource allocation for services running inside Ubuntu container

CONTAINER_NAME="ubuntu-server"
HOST_TOTAL_MEMORY_GB=128
CONTAINER_MEMORY_GB=96
CONTAINER_CPUS=16

echo "Optimizing resources for nested Ubuntu container architecture"
echo "============================================================="
echo "Host Total Memory: `${HOST_TOTAL_MEMORY_GB}GB"
echo "Container Memory: `${CONTAINER_MEMORY_GB}GB"
echo "Container CPUs: `${CONTAINER_CPUS}"
echo ""

# Calculate optimal service resource allocation within container
OLLAMA_MEMORY_MB=`$((CONTAINER_MEMORY_GB * 30 * 1024 / 100))`  # 30% of container memory
N8N_MEMORY_MB=`$((CONTAINER_MEMORY_GB * 20 * 1024 / 100))`     # 20% of container memory
SUPABASE_MEMORY_MB=`$((CONTAINER_MEMORY_GB * 15 * 1024 / 100))` # 15% of container memory
OPENWEBUI_MEMORY_MB=`$((CONTAINER_MEMORY_GB * 10 * 1024 / 100))` # 10% of container memory
OTHER_MEMORY_MB=`$((CONTAINER_MEMORY_GB * 25 * 1024 / 100))`   # 25% for other services

OLLAMA_CPUS=`$(echo "scale=1; `$CONTAINER_CPUS * 40 / 100" | bc)`  # 40% of container CPUs
N8N_CPUS=`$(echo "scale=1; `$CONTAINER_CPUS * 25 / 100" | bc)`     # 25% of container CPUs
SUPABASE_CPUS=`$(echo "scale=1; `$CONTAINER_CPUS * 20 / 100" | bc)` # 20% of container CPUs
OTHER_CPUS=`$(echo "scale=1; `$CONTAINER_CPUS * 15 / 100" | bc)`   # 15% for other services

echo "Recommended Resource Allocation within Ubuntu Container:"
echo "======================================================="
echo "Memory Allocation (MB):"
echo "- Ollama: `$OLLAMA_MEMORY_MB MB"
echo "- N8N: `$N8N_MEMORY_MB MB"
echo "- Supabase/PostgreSQL: `$SUPABASE_MEMORY_MB MB"
echo "- OpenWebUI: `$OPENWEBUI_MEMORY_MB MB"
echo "- Other services: `$OTHER_MEMORY_MB MB"
echo ""
echo "CPU Allocation:"
echo "- Ollama: `$OLLAMA_CPUS cores"
echo "- N8N: `$N8N_CPUS cores"
echo "- Supabase/PostgreSQL: `$SUPABASE_CPUS cores"
echo "- Other services: `$OTHER_CPUS cores"
echo ""

# Copy optimized docker-compose.yml to container
echo "Copying optimized docker-compose.yml to Ubuntu container..."
if [ -f "docker-compose.yml" ]; then
    docker cp docker-compose.yml `$CONTAINER_NAME`:/app/docker-compose.yml
    echo "✓ docker-compose.yml copied to container"
else
    echo "✗ docker-compose.yml not found in current directory"
    exit 1
fi

# Apply resource limits to services inside container
echo ""
echo "Applying resource limits to services inside container..."

# Stop existing services if running
docker exec `$CONTAINER_NAME` docker compose -f /app/docker-compose.yml down 2>/dev/null || true

# Start services with resource limits
docker exec `$CONTAINER_NAME` docker compose -f /app/docker-compose.yml up -d

if [ `$?` -eq 0 ]; then
    echo "✓ Services started successfully with optimized resource limits"
else
    echo "✗ Failed to start services"
    exit 1
fi

echo ""
echo "Container Resource Optimization Complete"
echo "========================================"
echo ""
echo "Monitoring Commands:"
echo "==================="
echo "# Check container resource usage:"
echo "docker stats `$CONTAINER_NAME`"
echo ""
echo "# Check services inside container:"
echo "docker exec `$CONTAINER_NAME` docker ps"
echo ""
echo "# Monitor service resource usage:"
echo "docker exec `$CONTAINER_NAME` docker stats"
echo ""
echo "# Check container logs:"
echo "docker logs `$CONTAINER_NAME`"
echo ""
echo "# Check service logs:"
echo "docker exec `$CONTAINER_NAME` docker compose logs -f"
"@ | Out-File -FilePath "container-resource-optimization.sh" -Encoding UTF8

# Create container monitoring script
@"
#!/bin/bash
# Container Monitoring Script for Nested Architecture
# Monitors both host container and nested services

CONTAINER_NAME="ubuntu-server"
MONITORING_INTERVAL=30

echo "Container Performance Monitoring"
echo "==============================="
echo "Monitoring container: `$CONTAINER_NAME`"
echo "Update interval: `$MONITORING_INTERVAL` seconds"
echo ""

# Function to get container resource usage
get_container_stats() {
    echo "=== Container Resource Usage ==="
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" `$CONTAINER_NAME` 2>/dev/null || echo "Container not running"
    echo ""
}

# Function to get nested services stats
get_nested_services_stats() {
    echo "=== Nested Services Resource Usage ==="
    if docker exec `$CONTAINER_NAME` docker ps -q 2>/dev/null | grep -q .; then
        docker exec `$CONTAINER_NAME` docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || echo "Unable to get nested service stats"
    else
        echo "No nested services running"
    fi
    echo ""
}

# Function to check container health
check_container_health() {
    echo "=== Container Health Check ==="
    HEALTH_STATUS=`$(docker inspect `$CONTAINER_NAME` --format "{{.State.Health.Status}}" 2>/dev/null || echo "unknown")`

    if [ "`$HEALTH_STATUS`" = "healthy" ]; then
        echo "✓ Container health: HEALTHY"
    elif [ "`$HEALTH_STATUS`" = "unhealthy" ]; then
        echo "✗ Container health: UNHEALTHY"
    else
        echo "? Container health: `$HEALTH_STATUS`"
    fi

    # Check container resource limits
    CONTAINER_MEMORY=`$(docker inspect `$CONTAINER_NAME` --format "{{.HostConfig.Memory}}" 2>/dev/null | awk '{print `$1 / 1024 / 1024 / 1024 "GB"}')`
    CONTAINER_CPUS=`$(docker inspect `$CONTAINER_NAME` --format "{{.HostConfig.NanoCpus}}" 2>/dev/null | awk '{print `$1 / 1000000000}')`

    echo "Container limits: `${CONTAINER_MEMORY} memory, `${CONTAINER_CPUS} CPUs"
    echo ""
}

# Function to check nested services health
check_nested_services_health() {
    echo "=== Nested Services Health Check ==="
    RUNNING_SERVICES=`$(docker exec `$CONTAINER_NAME` docker ps --filter "status=running" --format "{{.Names}}" 2>/dev/null | wc -l)`
    TOTAL_SERVICES=`$(docker exec `$CONTAINER_NAME` docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l)`

    echo "Running services: `$RUNNING_SERVICES / `$TOTAL_SERVICES"

    if [ "`$RUNNING_SERVICES`" -lt "`$TOTAL_SERVICES`" ]; then
        echo "⚠ Some services are not running:"
        docker exec `$CONTAINER_NAME` docker ps -a --filter "status=exited" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || echo "Unable to list stopped services"
    fi
    echo ""
}

# Main monitoring loop
log_file="container-monitoring-$(date +%Y%m%d-%H%M%S).log"
echo "Logging to: `$log_file`"
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    timestamp=`$(date '+%Y-%m-%d %H:%M:%S')`
    echo "[$timestamp] Monitoring cycle started" >> "`$log_file`"

    get_container_stats | tee -a "`$log_file`"
    get_nested_services_stats | tee -a "`$log_file`"
    check_container_health | tee -a "`$log_file`"
    check_nested_services_health | tee -a "`$log_file`"

    echo "Monitoring cycle complete. Waiting `$MONITORING_INTERVAL` seconds..." | tee -a "`$log_file`"
    echo "----------------------------------------" >> "`$log_file`"
    sleep `$MONITORING_INTERVAL`
done
"@ | Out-File -FilePath "container-monitoring.sh" -Encoding UTF8

# Create container resource adjustment script
@"
#!/bin/bash
# Container Resource Adjustment Script
# Dynamically adjusts container resource limits based on usage

CONTAINER_NAME="ubuntu-server"
ADJUSTMENT_INTERVAL=300  # 5 minutes
MEMORY_THRESHOLD=80     # Adjust if usage > 80%
CPU_THRESHOLD=75        # Adjust if usage > 75%

echo "Container Resource Adjustment Service"
echo "===================================="
echo "Monitoring container: `$CONTAINER_NAME`"
echo "Adjustment interval: `$ADJUSTMENT_INTERVAL` seconds"
echo "Memory threshold: `$MEMORY_THRESHOLD`%"
echo "CPU threshold: `$CPU_THRESHOLD`%"
echo ""

log() {
    echo "[`$(date +'%Y-%m-%d %H:%M:%S')`] `$1`" | tee -a container-adjustments.log
}

get_container_memory_usage() {
    docker stats --no-stream --format "{{.MemPerc}}" `$CONTAINER_NAME` 2>/dev/null | sed 's/%//'
}

get_container_cpu_usage() {
    docker stats --no-stream --format "{{.CPUPerc}}" `$CONTAINER_NAME` 2>/dev/null | sed 's/%//'
}

adjust_container_memory() {
    CURRENT_MEMORY=`$(docker inspect `$CONTAINER_NAME` --format "{{.HostConfig.Memory}}" 2>/dev/null)`
    CURRENT_MEMORY_GB=`$(echo "scale=2; `$CURRENT_MEMORY / 1024 / 1024 / 1024" | bc 2>/dev/null)`

    # Increase memory by 25%
    NEW_MEMORY=`$(echo "`$CURRENT_MEMORY * 1.25" | bc | cut -d'.' -f1)`
    NEW_MEMORY_GB=`$(echo "scale=2; `$NEW_MEMORY / 1024 / 1024 / 1024" | bc 2>/dev/null)`

    log "Adjusting container memory from `${CURRENT_MEMORY_GB}GB to `${NEW_MEMORY_GB}GB"

    docker update --memory `$NEW_MEMORY `$CONTAINER_NAME` 2>/dev/null

    if [ `$?` -eq 0 ]; then
        log "✓ Container memory adjusted successfully"
    else
        log "✗ Failed to adjust container memory"
    fi
}

adjust_container_cpu() {
    CURRENT_CPUS=`$(docker inspect `$CONTAINER_NAME` --format "{{.HostConfig.NanoCpus}}" 2>/dev/null | awk '{print `$1 / 1000000000}')`

    # Increase CPU by 0.5 cores
    NEW_CPUS=`$(echo "`$CURRENT_CPUS + 0.5" | bc)`

    log "Adjusting container CPUs from `$CURRENT_CPUS to `$NEW_CPUS"

    docker update --cpus `$NEW_CPUS `$CONTAINER_NAME` 2>/dev/null

    if [ `$?` -eq 0 ]; then
        log "✓ Container CPU adjusted successfully"
    else
        log "✗ Failed to adjust container CPU"
    fi
}

# Main adjustment loop
log "Container resource adjustment service started"

while true; do
    if docker ps --filter "name=`$CONTAINER_NAME`" --filter "status=running" | grep -q "`$CONTAINER_NAME`"; then
        MEMORY_USAGE=`$(get_container_memory_usage)`
        CPU_USAGE=`$(get_container_cpu_usage)`

        ADJUSTMENT_MADE=false

        if [ ! -z "`$MEMORY_USAGE`" ] && (( `$(echo "`$MEMORY_USAGE` > `$MEMORY_THRESHOLD`" | bc -l)` )); then
            log "High memory usage detected: `$MEMORY_USAGE`%"
            adjust_container_memory
            ADJUSTMENT_MADE=true
        fi

        if [ ! -z "`$CPU_USAGE`" ] && (( `$(echo "`$CPU_USAGE` > `$CPU_THRESHOLD`" | bc -l)` )); then
            log "High CPU usage detected: `$CPU_USAGE`%"
            adjust_container_cpu
            ADJUSTMENT_MADE=true
        fi

        if [ "`$ADJUSTMENT_MADE`" = "false" ]; then
            log "Resource usage within normal limits"
        fi
    else
        log "Container `$CONTAINER_NAME` is not running"
    fi

    sleep `$ADJUSTMENT_INTERVAL`
done
"@ | Out-File -FilePath "container-resource-adjustment.sh" -Encoding UTF8

Write-Host "Container resource optimization scripts created." -ForegroundColor Green
Write-Host ""
Write-Host "Files created:" -ForegroundColor Cyan
Write-Host "- container-resource-optimization.sh: Applies optimized resource limits to nested services"
Write-Host "- container-monitoring.sh: Monitors both container and nested service performance"
Write-Host "- container-resource-adjustment.sh: Dynamically adjusts container resources based on usage"
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "1. Run './container-resource-optimization.sh' to apply optimized resource allocation"
Write-Host "2. Run './container-monitoring.sh' for continuous performance monitoring"
Write-Host "3. Run './container-resource-adjustment.sh &' for automatic resource adjustment (background)"
Write-Host ""
Write-Host "Updated Ubuntu Container Limits:" -ForegroundColor Yellow
Write-Host "- Memory: 96GB (up from 64GB)"
Write-Host "- CPUs: 16 cores (up from 12 cores)"
Write-Host "- Memory Swap: 128GB"
Write-Host "- Kernel Memory: 16GB"
Write-Host "- PIDs Limit: 8192 (up from 4096)"
Write-Host "- File Descriptors: 8192 (up from 4096)"
Write-Host "- Processes: 2048 (up from 1024)"
Write-Host ""
Write-Host "This ensures the Ubuntu container can accommodate all nested services with Phase 7 optimizations."