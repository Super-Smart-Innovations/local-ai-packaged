# Phase 7: Performance Monitoring and Alerting Scripts
# This script creates comprehensive monitoring and alerting for performance optimization

Write-Host "Creating performance monitoring and alerting scripts..." -ForegroundColor Green

# Create comprehensive monitoring script
@"
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
    echo "[`$(date +'%Y-%m-%d %H:%M:%S')`] `$1`" >> "`$LOG_FILE`"
}

alert() {
    echo "[ALERT] [`$(date +'%Y-%m-%d %H:%M:%S')`] `$1`" | tee -a "`$ALERT_FILE`" >&2
}

get_service_health() {
    SERVICE_NAME=`$1`
    if docker ps --filter "name=`$SERVICE_NAME`" --filter "status=running" | grep -q "`$SERVICE_NAME`"; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

get_memory_usage() {
    SERVICE_NAME=`$1`
    docker stats --no-stream --format "{{.MemPerc}}" `$SERVICE_NAME` 2>/dev/null | sed 's/%//'
}

get_cpu_usage() {
    SERVICE_NAME=`$1`
    docker stats --no-stream --format "{{.CPUPerc}}" `$SERVICE_NAME` 2>/dev/null | sed 's/%//'
}

get_disk_usage() {
    df / | tail -1 | awk '{print `$5}' | sed 's/%//'
}

check_service_performance() {
    SERVICE_NAME=`$1`

    HEALTH=`$(get_service_health `$SERVICE_NAME`)`
    if [ "`$HEALTH`" != "healthy" ]; then
        alert "Service `$SERVICE_NAME` is not healthy"
        return
    fi

    MEMORY_USAGE=`$(get_memory_usage `$SERVICE_NAME`)`
    CPU_USAGE=`$(get_cpu_usage `$SERVICE_NAME`)`

    log "Service: `$SERVICE_NAME` - Memory: `$MEMORY_USAGE`% - CPU: `$CPU_USAGE`%"

    if [ ! -z "`$MEMORY_USAGE`" ] && (( `$(echo "`$MEMORY_USAGE` > `$MEMORY_THRESHOLD`" | bc -l)` )); then
        alert "High memory usage on `$SERVICE_NAME`: `$MEMORY_USAGE`%"
    fi

    if [ ! -z "`$CPU_USAGE`" ] && (( `$(echo "`$CPU_USAGE` > `$CPU_THRESHOLD`" | bc -l)` )); then
        alert "High CPU usage on `$SERVICE_NAME`: `$CPU_USAGE`%"
    fi
}

monitor_database_performance() {
    if docker ps --filter "name=postgres" --filter "status=running" | grep -q "postgres"; then
        log "Monitoring PostgreSQL performance..."

        # Get active connections
        CONNECTIONS=`$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null)`
        log "PostgreSQL active connections: `$CONNECTIONS`"

        # Check for long-running queries
        LONG_QUERIES=`$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '30 seconds';" 2>/dev/null)`
        if [ "`$LONG_QUERIES`" -gt 0 ]; then
            alert "PostgreSQL has `$LONG_QUERIES` long-running queries (>30s)"
        fi

        # Check cache hit ratio
        CACHE_RATIO=`$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT round(sum(blks_hit)*100/sum(blks_hit+blks_read), 2) as cache_hit_ratio FROM pg_stat_database WHERE blks_read > 0;" 2>/dev/null)`
        log "PostgreSQL cache hit ratio: `$CACHE_RATIO`%"
    fi
}

monitor_redis_performance() {
    if docker ps --filter "name=redis" --filter "status=running" | grep -q "redis"; then
        log "Monitoring Redis performance..."

        # Get Redis stats
        REDIS_INFO=`$(docker exec redis redis-cli -a LOCALONLYREDIS INFO stats 2>/dev/null)`

        # Extract key metrics
        TOTAL_CONNECTIONS=`$(echo "`$REDIS_INFO`" | grep "total_connections_received" | cut -d':' -f2)`
        EVICTED_KEYS=`$(echo "`$REDIS_INFO`" | grep "evicted_keys" | cut -d':' -f2)`
        KEYSPACE_HITS=`$(echo "`$REDIS_INFO`" | grep "keyspace_hits" | cut -d':' -f2)`
        KEYSPACE_MISSES=`$(echo "`$REDIS_INFO`" | grep "keyspace_misses" | cut -d':' -f2)`

        log "Redis connections: `$TOTAL_CONNECTIONS`, evicted: `$EVICTED_KEYS`, hits: `$KEYSPACE_HITS`, misses: `$KEYSPACE_MISSES`"

        # Calculate hit ratio
        if [ "`$KEYSPACE_HITS`" -gt 0 ] || [ "`$KEYSPACE_MISSES`" -gt 0 ]; then
            HIT_RATIO=`$(echo "scale=2; `$KEYSPACE_HITS` * 100 / (`$KEYSPACE_HITS` + `$KEYSPACE_MISSES`)" | bc)`
            log "Redis hit ratio: `$HIT_RATIO`%"

            if (( `$(echo "`$HIT_RATIO` < 80" | bc -l)` )); then
                alert "Low Redis cache hit ratio: `$HIT_RATIO`%"
            fi
        fi
    fi
}

monitor_system_resources() {
    # Monitor disk usage
    DISK_USAGE=`$(get_disk_usage)`
    log "Disk usage: `$DISK_USAGE`%"

    if [ "`$DISK_USAGE`" -gt "`$DISK_THRESHOLD`" ]; then
        alert "High disk usage: `$DISK_USAGE`%"
    fi

    # Monitor system load
    LOAD_AVERAGE=`$(uptime | awk -F'load average:' '{ print `$2 }' | cut -d',' -f1 | xargs)`
    log "System load average: `$LOAD_AVERAGE`"

    # Check for high load (rough heuristic: load > number of cores)
    CPU_CORES=`$(nproc 2>/dev/null || echo "4")`
    if (( `$(echo "`$LOAD_AVERAGE` > `$CPU_CORES`" | bc -l)` )); then
        alert "High system load: `$LOAD_AVERAGE` (cores: `$CPU_CORES`)"
    fi
}

# Main monitoring loop
echo "Starting comprehensive performance monitoring..."
echo "Monitoring interval: `$MONITORING_INTERVAL` seconds"
echo "Log file: `$LOG_FILE`"
echo "Alert file: `$ALERT_FILE`"
echo "Press Ctrl+C to stop"

log "Performance monitoring started"

while true; do
    # Monitor critical services
    SERVICES=("n8n" "open-webui" "ollama" "postgres" "redis" "caddy")

    for service in "`${SERVICES[@]}"; do
        check_service_performance `$service`
    done

    # Monitor databases
    monitor_database_performance
    monitor_redis_performance

    # Monitor system resources
    monitor_system_resources

    sleep `$MONITORING_INTERVAL`
done
"@ | Out-File -FilePath "performance-monitor.sh" -Encoding UTF8

# Create alerting and notification script
@"
#!/bin/bash
# Performance Alerting and Notification Script
# Processes alerts and sends notifications

ALERT_FILE="performance-alerts.log"
NOTIFICATION_COOLDOWN=300  # 5 minutes between similar alerts
NOTIFICATION_CONFIG="alert-config.json"

# Default notification configuration
DEFAULT_CONFIG='{
  "email": {
    "enabled": false,
    "smtp_server": "",
    "smtp_port": 587,
    "username": "",
    "password": "",
    "to_address": ""
  },
  "slack": {
    "enabled": false,
    "webhook_url": "",
    "channel": "#alerts"
  },
  "webhook": {
    "enabled": false,
    "url": "",
    "headers": {}
  }
}'

# Create default config if it doesn't exist
if [ ! -f "`$NOTIFICATION_CONFIG`" ]; then
    echo "`$DEFAULT_CONFIG`" > "`$NOTIFICATION_CONFIG`"
    echo "Created default notification configuration: `$NOTIFICATION_CONFIG`"
    echo "Edit this file to enable notifications"
fi

# Track last notification times to prevent spam
declare -A LAST_NOTIFICATIONS

send_email_alert() {
    SUBJECT="`$1`"
    MESSAGE="`$2`"

    if command -v sendmail &> /dev/null; then
        echo "Subject: `$SUBJECT`" | sendmail -t "`$EMAIL_RECIPIENT`"
        echo "Email alert sent to `$EMAIL_RECIPIENT`"
    else
        echo "sendmail not available, skipping email notification"
    fi
}

send_slack_alert() {
    MESSAGE="`$1`"

    if [ ! -z "`$SLACK_WEBHOOK`" ]; then
        curl -X POST -H 'Content-type: application/json' \
             --data "{\"text\":\"`$MESSAGE\"}" \
             "`$SLACK_WEBHOOK`" 2>/dev/null
        echo "Slack alert sent"
    fi
}

send_webhook_alert() {
    ALERT_DATA="`$1`"

    if [ ! -z "`$WEBHOOK_URL`" ]; then
        curl -X POST -H "Content-Type: application/json" \
             -d "`$ALERT_DATA`" \
             "`$WEBHOOK_URL`" 2>/dev/null
        echo "Webhook alert sent"
    fi
}

process_alert() {
    ALERT_MESSAGE="`$1`"
    ALERT_TYPE="`$2`"
    CURRENT_TIME=`$(date +%s)`

    # Check cooldown
    LAST_TIME="`${LAST_NOTIFICATIONS[`$ALERT_TYPE`]}"
    if [ ! -z "`$LAST_TIME`" ]; then
        TIME_DIFF=`$((CURRENT_TIME - LAST_TIME))`
        if [ "`$TIME_DIFF`" -lt "`$NOTIFICATION_COOLDOWN`" ]; then
            echo "Alert '$ALERT_TYPE' in cooldown, skipping notification"
            return
        fi
    fi

    LAST_NOTIFICATIONS[`$ALERT_TYPE`]=$CURRENT_TIME

    echo "Processing alert: `$ALERT_MESSAGE`"

    # Load notification configuration
    if [ -f "`$NOTIFICATION_CONFIG`" ]; then
        EMAIL_ENABLED=`$(jq -r '.email.enabled // false' `$NOTIFICATION_CONFIG`)`
        SLACK_ENABLED=`$(jq -r '.slack.enabled // false' `$NOTIFICATION_CONFIG`)`
        WEBHOOK_ENABLED=`$(jq -r '.webhook.enabled // false' `$NOTIFICATION_CONFIG`)`

        EMAIL_RECIPIENT=`$(jq -r '.email.to_address // empty' `$NOTIFICATION_CONFIG`)`
        SLACK_WEBHOOK=`$(jq -r '.slack.webhook_url // empty' `$NOTIFICATION_CONFIG`)`
        WEBHOOK_URL=`$(jq -r '.webhook.url // empty' `$NOTIFICATION_CONFIG`)`
    fi

    # Send notifications based on configuration
    if [ "`$EMAIL_ENABLED`" = "true" ] && [ ! -z "`$EMAIL_RECIPIENT`" ]; then
        send_email_alert "Performance Alert: `$ALERT_TYPE`" "`$ALERT_MESSAGE`"
    fi

    if [ "`$SLACK_ENABLED`" = "true" ] && [ ! -z "`$SLACK_WEBHOOK`" ]; then
        send_slack_alert "`$ALERT_MESSAGE`"
    fi

    if [ "`$WEBHOOK_ENABLED`" = "true" ] && [ ! -z "`$WEBHOOK_URL`" ]; then
        ALERT_DATA="{\"alert_type\":\"`$ALERT_TYPE`\",\"message\":\"`$ALERT_MESSAGE`\",\"timestamp\":\"`$(date -Iseconds)`\"}"
        send_webhook_alert "`$ALERT_DATA`"
    fi
}

# Monitor alert file for new alerts
echo "Starting alert processor..."
echo "Monitoring: `$ALERT_FILE`"
echo "Config: `$NOTIFICATION_CONFIG`"

if [ ! -f "`$ALERT_FILE`" ]; then
    echo "Alert file does not exist yet. It will be created when alerts occur."
    exit 1
fi

# Process existing alerts
tail -f "`$ALERT_FILE`" | while read line; do
    if [[ `$line` == *"[ALERT]"* ]]; then
        ALERT_MESSAGE=`$(echo `$line` | sed 's/\[ALERT\]\s*\[[^]]*\]\s*//')`
        ALERT_TYPE=`$(echo `$ALERT_MESSAGE` | awk '{print `$1}')`  # First word as type
        process_alert "`$ALERT_MESSAGE`" "`$ALERT_TYPE`"
    fi
done
"@ | Out-File -FilePath "performance-alerts.sh" -Encoding UTF8

# Create performance dashboard script
@"
#!/bin/bash
# Performance Dashboard Script
# Generates HTML dashboard with current performance metrics

DASHBOARD_FILE="performance-dashboard.html"
CSS_STYLE="
<style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .metric { background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 5px; }
    .healthy { border-left: 5px solid #4CAF50; }
    .warning { border-left: 5px solid #FF9800; }
    .critical { border-left: 5px solid #F44336; }
    .header { background: #2196F3; color: white; padding: 15px; border-radius: 5px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
    .chart { width: 100%; height: 200px; background: #f9f9f9; border-radius: 5px; display: flex; align-items: center; justify-content: center; }
</style>
"

generate_metric_html() {
    NAME="`$1`"
    VALUE="`$2`"
    STATUS="`$3`"  # healthy, warning, critical
    UNIT="`$4`"

    echo "<div class='metric `$STATUS`'>"
    echo "<h3>`$NAME`</h3>"
    echo "<div style='font-size: 24px; font-weight: bold;'>`$VALUE` `$UNIT`</div>"
    echo "</div>"
}

generate_dashboard() {
    echo "<!DOCTYPE html>
<html>
<head>
    <title>Performance Dashboard</title>
    `$CSS_STYLE`
    <meta http-equiv='refresh' content='30'>
</head>
<body>
    <div class='header'>
        <h1>🚀 Performance Dashboard</h1>
        <p>Last updated: `$(date)`</p>
    </div>

    <div class='grid'>" > "`$DASHBOARD_FILE`"

    # System metrics
    CPU_LOAD=`$(uptime | awk -F'load average:' '{ print `$2 }' | cut -d',' -f1 | xargs)`
    MEMORY_USAGE=`$(free | grep Mem | awk '{printf "%.0f", `$3`/`$2` * 100.0}')`
    DISK_USAGE=`$(df / | tail -1 | awk '{print `$5}' | sed 's/%//')`

    generate_metric_html "CPU Load Average" "`$CPU_LOAD`" "healthy" "" >> "`$DASHBOARD_FILE`"
    generate_metric_html "Memory Usage" "`$MEMORY_USAGE`" "healthy" "%" >> "`$DASHBOARD_FILE`"
    generate_metric_html "Disk Usage" "`$DISK_USAGE`" "healthy" "%" >> "`$DASHBOARD_FILE`"

    # Docker services
    SERVICES=("n8n" "open-webui" "ollama" "postgres" "redis")

    for service in "`${SERVICES[@]}"; do
        if docker ps --filter "name=`$service`" --filter "status=running" | grep -q "`$service`"; then
            MEMORY=`$(docker stats --no-stream --format "{{.MemPerc}}" `$service` 2>/dev/null | sed 's/%//')`
            CPU=`$(docker stats --no-stream --format "{{.CPUPerc}}" `$service` 2>/dev/null | sed 's/%//')`

            STATUS="healthy"
            if [ ! -z "`$MEMORY`" ] && (( `$(echo "`$MEMORY` > 85" | bc -l)` )); then STATUS="critical"; fi
            if [ ! -z "`$CPU`" ] && (( `$(echo "`$CPU` > 80" | bc -l)` )); then STATUS="warning"; fi

            generate_metric_html "`$service` Memory" "`$MEMORY`" "`$STATUS`" "%" >> "`$DASHBOARD_FILE`"
            generate_metric_html "`$service` CPU" "`$CPU`" "`$STATUS`" "%" >> "`$DASHBOARD_FILE`"
        else
            generate_metric_html "`$service` Status" "DOWN" "critical" "" >> "`$DASHBOARD_FILE`"
        fi
    done

    # Database metrics (if available)
    if docker ps --filter "name=postgres" --filter "status=running" | grep -q "postgres"; then
        CONNECTIONS=`$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null)`
        generate_metric_html "DB Connections" "`$CONNECTIONS`" "healthy" "" >> "`$DASHBOARD_FILE`"
    fi

    echo "    </div>
    <div class='chart'>📊 Real-time Charts Coming Soon</div>
</body>
</html>" >> "`$DASHBOARD_FILE`"

    echo "Dashboard generated: `$DASHBOARD_FILE`"
}

# Generate initial dashboard
generate_dashboard

echo "Performance dashboard is being served."
echo "Open `$DASHBOARD_FILE` in a web browser."
echo "Dashboard auto-refreshes every 30 seconds."
"@ | Out-File -FilePath "performance-dashboard.sh" -Encoding UTF8

# Create automated performance testing script
@"
#!/bin/bash
# Automated Performance Testing Script
# Runs regular performance tests and generates reports

TEST_RESULTS_DIR="performance-test-results"
mkdir -p `$TEST_RESULTS_DIR`

run_performance_test() {
    TEST_NAME="`$1`"
    TEST_COMMAND="`$2`"
    EXPECTED_MAX_TIME="`$3`"

    START_TIME=`$(date +%s%N)`
    `$TEST_COMMAND` > /dev/null 2>&1
    END_TIME=`$(date +%s%N)`

    EXECUTION_TIME=`$(echo "scale=2; (`$END_TIME` - `$START_TIME`) / 1000000" | bc)`

    RESULT="PASS"
    if (( `$(echo "`$EXECUTION_TIME` > `$EXPECTED_MAX_TIME`" | bc -l)` )); then
        RESULT="FAIL"
    fi

    echo "`$TEST_NAME`: `$EXECUTION_TIME`ms - `$RESULT`"
    echo "`$(date +'%Y-%m-%d %H:%M:%S')`, `$TEST_NAME`, `$EXECUTION_TIME`, `$RESULT`" >> "`$TEST_RESULTS_DIR`/latest.csv"
}

echo "Running automated performance tests..."
echo "====================================="

# Test container startup time
run_performance_test "Container Startup" "docker run --rm hello-world" 500

# Test database connection
run_performance_test "Database Connection" "docker exec postgres pg_isready -U postgres" 100

# Test Redis connection
run_performance_test "Redis Connection" "docker exec redis redis-cli ping" 50

# Test API endpoints (if services are running)
if curl -s http://localhost:5678/health > /dev/null 2>&1; then
    run_performance_test "N8N Health Check" "curl -s http://localhost:5678/health" 200
fi

if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
    run_performance_test "OpenWebUI Health Check" "curl -s http://localhost:3000/api/health" 200
fi

echo ""
echo "Performance test completed."
echo "Results saved to: `$TEST_RESULTS_DIR`/latest.csv"

# Generate summary report
TOTAL_TESTS=`$(wc -l < `$TEST_RESULTS_DIR`/latest.csv)`
PASSED_TESTS=`$(grep "PASS" `$TEST_RESULTS_DIR`/latest.csv | wc -l)`
FAILED_TESTS=`$((TOTAL_TESTS - PASSED_TESTS))`

echo "Summary: `$PASSED_TESTS` passed, `$FAILED_TESTS` failed out of `$TOTAL_TESTS` tests"

if [ "`$FAILED_TESTS`" -gt 0 ]; then
    echo "❌ Performance regression detected!"
    echo "Check the detailed results for failing tests."
else
    echo "✅ All performance tests passed."
fi
"@ | Out-File -FilePath "performance-testing.sh" -Encoding ASCII

Write-Host "Performance monitoring and alerting scripts created." -ForegroundColor Green
Write-Host ""
Write-Host "Scripts created:" -ForegroundColor Cyan
Write-Host "- performance-monitor.sh: Comprehensive real-time monitoring"
Write-Host "- performance-alerts.sh: Alert processing and notifications"
Write-Host "- performance-dashboard.sh: HTML dashboard generation"
Write-Host "- performance-testing.sh: Automated performance testing"
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "1. Run './performance-monitor.sh' for continuous monitoring"
Write-Host "2. Run './performance-alerts.sh' to process alerts"
Write-Host "3. Run './performance-dashboard.sh' to generate HTML dashboard"
Write-Host "4. Schedule './performance-testing.sh' for regular testing"
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "- Edit alert-config.json to enable email/Slack/webhook notifications"
Write-Host "- Adjust thresholds in performance-monitor.sh as needed"
Write-Host "- Dashboard auto-refreshes every 30 seconds"