#!/bin/bash

# Phase 5: Performance Monitoring Setup for Ubuntu Container
# This script implements comprehensive performance monitoring inside the container

set -e

LOG_DIR="/var/log/localai"
MONITORING_DIR="$LOG_DIR/monitoring"
PERFORMANCE_DIR="$LOG_DIR/performance"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Function to create resource utilization tracking
create_resource_utilization_tracking() {
    echo "Creating resource utilization tracking..."

    mkdir -p "$PERFORMANCE_DIR"

    cat > "$PERFORMANCE_DIR/resource-tracking.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
METRICS_FILE="$LOG_DIR/performance/resource-metrics.csv"

# Create CSV header if not exists
if [ ! -f "$METRICS_FILE" ]; then
    echo "Timestamp,CPU_Usage,MEM_Usage,Disk_Read_MBps,Disk_Write_MBps,Load_1m,Load_5m,Load_15m" > "$METRICS_FILE"
fi

# Get CPU usage (percentage)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

# Get memory usage (percentage)
MEM_USAGE=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')

# Get disk I/O (simplified - requires iotop or similar)
DISK_READ_MBPS="N/A"
DISK_WRITE_MBPS="N/A"
if command -v iostat &> /dev/null; then
    DISK_STATS=$(iostat -d 1 1 | grep -A1 "Device:" | tail -1)
    # This is a simplified extraction - would need proper parsing
fi

# Get system load
LOAD_1M=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | xargs)
LOAD_5M=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f2 | xargs)
LOAD_15M=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f3 | xargs)

# Write metrics to CSV
echo "$TIMESTAMP,$CPU_USAGE,$MEM_USAGE,$DISK_READ_MBPS,$DISK_WRITE_MBPS,$LOAD_1M,$LOAD_5M,$LOAD_15M" >> "$METRICS_FILE"

# Check for performance thresholds
if (( $(echo "$CPU_USAGE > 90" | bc -l) )); then
    echo "$TIMESTAMP - CRITICAL: CPU usage at ${CPU_USAGE}%" >> "$LOG_DIR/alerts/performance-alerts.log"
fi

if (( $(echo "$MEM_USAGE > 95" | bc -l) )); then
    echo "$TIMESTAMP - CRITICAL: Memory usage at ${MEM_USAGE}%" >> "$LOG_DIR/alerts/performance-alerts.log"
fi

if (( $(echo "$LOAD_1M > $(nproc)" | bc -l) )); then
    echo "$TIMESTAMP - WARNING: High load average: ${LOAD_1M}" >> "$LOG_DIR/alerts/performance-alerts.log"
fi

echo "Resource metrics collected: CPU=${CPU_USAGE}%, MEM=${MEM_USAGE}%, Load=${LOAD_1M}"
EOF

    chmod +x "$PERFORMANCE_DIR/resource-tracking.sh"
    echo "Resource utilization tracking script created."
}

# Function to create service response time monitoring
create_service_response_monitoring() {
    echo "Creating service response time monitoring..."

    cat > "$PERFORMANCE_DIR/response-monitoring.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
RESPONSE_FILE="$LOG_DIR/performance/response-times.csv"

# Create CSV header if not exists
if [ ! -f "$RESPONSE_FILE" ]; then
    echo "Timestamp,n8n_Response_ms,OpenWebUI_Response_ms,Supabase_Response_ms,Qdrant_Response_ms,Neo4j_Response_ms" > "$RESPONSE_FILE"
fi

# Function to measure response time
measure_response_time() {
    local url="$1"
    local service="$2"
    local start_time=$(date +%s%N)
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)
    local end_time=$(date +%s%N)

    if [ "$response_code" = "200" ] || [ "$response_code" = "000" ]; then
        local response_time=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
        echo "$response_time"
    else
        echo "ERROR"
    fi
}

# Test service response times
N8N_RESPONSE=$(measure_response_time "http://localhost:5678/healthz" "n8n")
OPENWEBUI_RESPONSE=$(measure_response_time "http://localhost:3000/api/health" "OpenWebUI")
SUPABASE_RESPONSE=$(measure_response_time "http://localhost:54321/rest/v1/" "Supabase")
QDRANT_RESPONSE=$(measure_response_time "http://localhost:6333/health" "Qdrant")
NEO4J_RESPONSE=$(measure_response_time "http://localhost:7474/" "Neo4j")

# Write metrics to CSV
echo "$TIMESTAMP,$N8N_RESPONSE,$OPENWEBUI_RESPONSE,$SUPABASE_RESPONSE,$QDRANT_RESPONSE,$NEO4J_RESPONSE" >> "$RESPONSE_FILE"

# Check for slow responses
check_response_time() {
    local service="$1"
    local response="$2"
    local threshold="$3"

    if [ "$response" != "ERROR" ] && [ "$response" -gt "$threshold" ]; then
        echo "$TIMESTAMP - WARNING: $service response time ${response}ms exceeds threshold ${threshold}ms" >> "$LOG_DIR/alerts/performance-alerts.log"
    elif [ "$response" = "ERROR" ]; then
        echo "$TIMESTAMP - ERROR: $service is not responding" >> "$LOG_DIR/alerts/performance-alerts.log"
    fi
}

check_response_time "n8n" "$N8N_RESPONSE" 5000
check_response_time "OpenWebUI" "$OPENWEBUI_RESPONSE" 3000
check_response_time "Supabase" "$SUPABASE_RESPONSE" 2000
check_response_time "Qdrant" "$QDRANT_RESPONSE" 1000
check_response_time "Neo4j" "$NEO4J_RESPONSE" 2000

echo "Service response times measured: n8n=${N8N_RESPONSE}ms, OpenWebUI=${OPENWEBUI_RESPONSE}ms"
EOF

    chmod +x "$PERFORMANCE_DIR/response-monitoring.sh"
    echo "Service response time monitoring script created."
}

# Function to create database performance metrics
create_database_performance_metrics() {
    echo "Creating database performance metrics..."

    cat > "$PERFORMANCE_DIR/database-monitoring.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DB_METRICS_FILE="$LOG_DIR/performance/database-metrics.csv"

# Create CSV header if not exists
if [ ! -f "$DB_METRICS_FILE" ]; then
    echo "Timestamp,Postgres_Connections,Postgres_Cache_Hit_Ratio,Neo4j_Heap_Used_MB" > "$DB_METRICS_FILE"
fi

# Function to get PostgreSQL metrics (if accessible)
get_postgres_metrics() {
    # This would need to be customized based on your database access
    # For now, return placeholder values
    echo "N/A,N/A"
}

# Function to get Neo4j metrics (if accessible)
get_neo4j_metrics() {
    # Attempt to get basic metrics from Neo4j
    if curl -s "http://localhost:7474/db/data/" > /dev/null 2>&1; then
        # This is a simplified check - real implementation would parse JMX metrics
        echo "N/A"
    else
        echo "ERROR"
    fi
}

# Collect database metrics
POSTGRES_METRICS=$(get_postgres_metrics)
NEO4J_METRICS=$(get_neo4j_metrics)

# Write metrics to CSV
echo "$TIMESTAMP,$POSTGRES_METRICS,$NEO4J_METRICS" >> "$DB_METRICS_FILE"

# Basic alerting
if [ "$NEO4J_METRICS" = "ERROR" ]; then
    echo "$TIMESTAMP - ERROR: Cannot access Neo4j metrics" >> "$LOG_DIR/alerts/performance-alerts.log"
fi

echo "Database performance metrics collected"
EOF

    chmod +x "$PERFORMANCE_DIR/database-monitoring.sh"
    echo "Database performance metrics script created."
}

# Function to create container health and restart tracking
create_container_health_tracking() {
    echo "Creating container health and restart tracking..."

    cat > "$PERFORMANCE_DIR/container-monitoring.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
CONTAINER_METRICS_FILE="$LOG_DIR/performance/container-metrics.csv"

# Create CSV header if not exists
if [ ! -f "$CONTAINER_METRICS_FILE" ]; then
    echo "Timestamp,Container_Name,Status,CPU_Usage,Memory_Usage,Restart_Count" > "$CONTAINER_METRICS_FILE"
fi

# Get container stats if Docker is available
if command -v docker &> /dev/null; then
    # Get container information
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Restarts}}" | tail -n +2 | while read -r line; do
        CONTAINER_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $2}')
        RESTARTS=$(echo "$line" | awk '{print $3}')

        # Get resource usage
        STATS=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}" "$CONTAINER_NAME" 2>/dev/null)
        if [ -n "$STATS" ]; then
            CPU_USAGE=$(echo "$STATS" | awk '{print $1}')
            MEM_USAGE=$(echo "$STATS" | awk '{print $2}')
        else
            CPU_USAGE="N/A"
            MEM_USAGE="N/A"
        fi

        # Write metrics to CSV
        echo "$TIMESTAMP,$CONTAINER_NAME,$STATUS,$CPU_USAGE,$MEM_USAGE,$RESTARTS" >> "$CONTAINER_METRICS_FILE"

        # Alert on container restarts
        if [ "$RESTARTS" -gt 0 ]; then
            echo "$TIMESTAMP - WARNING: Container $CONTAINER_NAME has restarted $RESTARTS times" >> "$LOG_DIR/alerts/performance-alerts.log"
        fi

        # Alert on unhealthy containers
        if echo "$STATUS" | grep -q "unhealthy\|exited\|dead"; then
            echo "$TIMESTAMP - CRITICAL: Container $CONTAINER_NAME is in bad state: $STATUS" >> "$LOG_DIR/alerts/performance-alerts.log"
        fi
    done

    echo "Container health metrics collected for all containers"
else
    echo "$TIMESTAMP,ERROR,Docker not available,N/A,N/A,N/A" >> "$CONTAINER_METRICS_FILE"
    echo "Docker not available for container monitoring"
fi
EOF

    chmod +x "$PERFORMANCE_DIR/container-monitoring.sh"
    echo "Container health tracking script created."
}

# Function to create comprehensive performance monitoring script
create_comprehensive_performance_monitoring() {
    echo "Creating comprehensive performance monitoring script..."

    cat > "$PERFORMANCE_DIR/comprehensive-monitoring.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
PERFORMANCE_DIR="$LOG_DIR/performance"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== Comprehensive Performance Monitoring - $TIMESTAMP ==="

# Run all performance monitoring scripts
if [ -f "$PERFORMANCE_DIR/resource-tracking.sh" ]; then
    bash "$PERFORMANCE_DIR/resource-tracking.sh"
fi

if [ -f "$PERFORMANCE_DIR/response-monitoring.sh" ]; then
    bash "$PERFORMANCE_DIR/response-monitoring.sh"
fi

if [ -f "$PERFORMANCE_DIR/database-monitoring.sh" ]; then
    bash "$PERFORMANCE_DIR/database-monitoring.sh"
fi

if [ -f "$PERFORMANCE_DIR/container-monitoring.sh" ]; then
    bash "$PERFORMANCE_DIR/container-monitoring.sh"
fi

echo "Comprehensive performance monitoring completed at $TIMESTAMP"
EOF

    chmod +x "$PERFORMANCE_DIR/comprehensive-monitoring.sh"
    echo "Comprehensive performance monitoring script created."
}

# Function to set up cron jobs for performance monitoring
setup_performance_cron_jobs() {
    echo "Setting up cron jobs for performance monitoring..."

    # Comprehensive monitoring every 30 seconds
    (crontab -l 2>/dev/null; echo "*/1 * * * * $PERFORMANCE_DIR/comprehensive-monitoring.sh") | crontab -

    echo "Performance monitoring cron jobs configured."
}

# Function to install performance monitoring tools
install_performance_tools() {
    echo "Installing performance monitoring tools..."

    apt-get update -qq

    # Install required tools
    apt-get install -y \
        bc \
        curl \
        sysstat \
        iotop \
        htop \
        jq

    echo "Performance monitoring tools installed."
}

# Main execution
case "$1" in
    "install")
        mkdir -p "$PERFORMANCE_DIR"
        install_performance_tools
        ;;
    "setup")
        mkdir -p "$PERFORMANCE_DIR"
        create_resource_utilization_tracking
        create_service_response_monitoring
        create_database_performance_metrics
        create_container_health_tracking
        create_comprehensive_performance_monitoring
        setup_performance_cron_jobs
        ;;
    "monitor")
        "$PERFORMANCE_DIR/comprehensive-monitoring.sh"
        ;;
    "resources")
        "$PERFORMANCE_DIR/resource-tracking.sh"
        ;;
    "response")
        "$PERFORMANCE_DIR/response-monitoring.sh"
        ;;
    "database")
        "$PERFORMANCE_DIR/database-monitoring.sh"
        ;;
    "containers")
        "$PERFORMANCE_DIR/container-monitoring.sh"
        ;;
    *)
        echo "Usage: $0 {install|setup|monitor|resources|response|database|containers}"
        echo "  install    - Install performance monitoring tools"
        echo "  setup      - Full performance monitoring setup"
        echo "  monitor    - Run comprehensive monitoring manually"
        echo "  resources  - Run resource tracking manually"
        echo "  response   - Run response time monitoring manually"
        echo "  database   - Run database monitoring manually"
        echo "  containers - Run container monitoring manually"
        exit 1
        ;;
esac

echo "Performance monitoring setup completed for Ubuntu container."