#!/bin/bash
# Comprehensive Performance Monitoring Script
# Monitors all services and provides real-time performance metrics

MONITORING_INTERVAL=30  # seconds
LOG_FILE="performance-monitoring.log"
ALERT_FILE="performance-alerts.log"

# Thresholds for alerting
MEMORY_THRESHOLD=85
CPU_THRESHOLD=80
DISK_THRESHOLD=90
NETWORK_LATENCY_THRESHOLD=100  # ms

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

alert() {
    echo "[ALERT] [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ALERT_FILE" >&2
}

get_service_health() {
    SERVICE_NAME=$1
    if docker ps --filter "name=$SERVICE_NAME" --filter "status=running" | grep -q "$SERVICE_NAME"; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

get_memory_usage() {
    SERVICE_NAME=$1
    docker stats --no-stream --format "{{.MemPerc}}" $SERVICE_NAME 2>/dev/null | sed 's/%//'
}

get_cpu_usage() {
    SERVICE_NAME=$1
    docker stats --no-stream --format "{{.CPUPerc}}" $SERVICE_NAME 2>/dev/null | sed 's/%//'
}

get_disk_usage() {
    df / | tail -1 | awk '{print $5}' | sed 's/%//'
}

check_service_performance() {
    SERVICE_NAME=$1

    HEALTH=$(get_service_health $SERVICE_NAME)
    if [ "$HEALTH" != "healthy" ]; then
        alert "Service $SERVICE_NAME is not healthy"
        return
    fi

    MEMORY_USAGE=$(get_memory_usage $SERVICE_NAME)
    CPU_USAGE=$(get_cpu_usage $SERVICE_NAME)

    log "Service: $SERVICE_NAME - Memory: $MEMORY_USAGE% - CPU: $CPU_USAGE%"

    if [ ! -z "$MEMORY_USAGE" ] && (( $(echo "$MEMORY_USAGE > $MEMORY_THRESHOLD" | bc -l) )); then
        alert "High memory usage on $SERVICE_NAME: $MEMORY_USAGE%"
    fi

    if [ ! -z "$CPU_USAGE" ] && (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
        alert "High CPU usage on $SERVICE_NAME: $CPU_USAGE%"
    fi
}

monitor_database_performance() {
    if docker ps --filter "name=postgres" --filter "status=running" | grep -q "postgres"; then
        log "Monitoring PostgreSQL performance..."

        # Get active connections
        CONNECTIONS=$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null)
        log "PostgreSQL active connections: $CONNECTIONS"

        # Check for long-running queries
        LONG_QUERIES=$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '30 seconds';" 2>/dev/null)
        if [ "$LONG_QUERIES" -gt 0 ]; then
            alert "PostgreSQL has $LONG_QUERIES long-running queries (>30s)"
        fi

        # Check cache hit ratio
        CACHE_RATIO=$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT round(sum(blks_hit)*100/sum(blks_hit+blks_read), 2) as cache_hit_ratio FROM pg_stat_database WHERE blks_read > 0;" 2>/dev/null)
        log "PostgreSQL cache hit ratio: $CACHE_RATIO%"
    fi
}

monitor_redis_performance() {
    if docker ps --filter "name=redis" --filter "status=running" | grep -q "redis"; then
        log "Monitoring Redis performance..."

        # Get Redis stats
        REDIS_INFO=$(docker exec redis redis-cli -a LOCALONLYREDIS INFO stats 2>/dev/null)

        # Extract key metrics
        TOTAL_CONNECTIONS=$(echo "$REDIS_INFO" | grep "total_connections_received" | cut -d':' -f2)
        EVICTED_KEYS=$(echo "$REDIS_INFO" | grep "evicted_keys" | cut -d':' -f2)
        KEYSPACE_HITS=$(echo "$REDIS_INFO" | grep "keyspace_hits" | cut -d':' -f2)
        KEYSPACE_MISSES=$(echo "$REDIS_INFO" | grep "keyspace_misses" | cut -d':' -f2)

        log "Redis connections: $TOTAL_CONNECTIONS, evicted: $EVICTED_KEYS, hits: $KEYSPACE_HITS, misses: $KEYSPACE_MISSES"

        # Calculate hit ratio
        if [ "$KEYSPACE_HITS" -gt 0 ] || [ "$KEYSPACE_MISSES" -gt 0 ]; then
            HIT_RATIO=$(echo "scale=2; $KEYSPACE_HITS * 100 / ($KEYSPACE_HITS + $KEYSPACE_MISSES)" | bc)
            log "Redis hit ratio: $HIT_RATIO%"

            if (( $(echo "$HIT_RATIO < 80" | bc -l) )); then
                alert "Low Redis cache hit ratio: $HIT_RATIO%"
            fi
        fi
    fi
}

monitor_system_resources() {
    # Monitor disk usage
    DISK_USAGE=$(get_disk_usage)
    log "Disk usage: $DISK_USAGE%"

    if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
        alert "High disk usage: $DISK_USAGE%"
    fi

    # Monitor system load
    LOAD_AVERAGE=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d',' -f1 | xargs)
    log "System load average: $LOAD_AVERAGE"

    # Check for high load (rough heuristic: load > number of cores)
    CPU_CORES=$(nproc 2>/dev/null || echo "4")
    if (( $(echo "$LOAD_AVERAGE > $CPU_CORES" | bc -l) )); then
        alert "High system load: $LOAD_AVERAGE (cores: $CPU_CORES)"
    fi
}

# Main monitoring loop
echo "Starting comprehensive performance monitoring..."
echo "Monitoring interval: $MONITORING_INTERVAL seconds"
echo "Log file: $LOG_FILE"
echo "Alert file: $ALERT_FILE"
echo "Press Ctrl+C to stop"

log "Performance monitoring started"

while true; do
    # Monitor critical services
    SERVICES=("n8n" "open-webui" "ollama" "postgres" "redis" "caddy")

    for service in "${SERVICES[@]}"; do
        check_service_performance $service
    done

    # Monitor databases
    monitor_database_performance
    monitor_redis_performance

    # Monitor system resources
    monitor_system_resources

    sleep $MONITORING_INTERVAL
done
