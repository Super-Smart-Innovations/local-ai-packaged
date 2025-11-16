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
    NAME="$1"
    VALUE="$2"
    STATUS="$3"  # healthy, warning, critical
    UNIT="$4"

    echo "<div class='metric $STATUS'>"
    echo "<h3>$NAME</h3>"
    echo "<div style='font-size: 24px; font-weight: bold;'>$VALUE $UNIT</div>"
    echo "</div>"
}

generate_dashboard() {
    echo "<!DOCTYPE html>
<html>
<head>
    <title>Performance Dashboard</title>
    $CSS_STYLE
    <meta http-equiv='refresh' content='30'>
</head>
<body>
    <div class='header'>
        <h1>ðŸš€ Performance Dashboard</h1>
        <p>Last updated: $(date)</p>
    </div>

    <div class='grid'>" > "$DASHBOARD_FILE"

    # System metrics
    CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d',' -f1 | xargs)
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    generate_metric_html "CPU Load Average" "$CPU_LOAD" "healthy" "" >> "$DASHBOARD_FILE"
    generate_metric_html "Memory Usage" "$MEMORY_USAGE" "healthy" "%" >> "$DASHBOARD_FILE"
    generate_metric_html "Disk Usage" "$DISK_USAGE" "healthy" "%" >> "$DASHBOARD_FILE"

    # Docker services
    SERVICES=("n8n" "open-webui" "ollama" "postgres" "redis")

    for service in "${SERVICES[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            MEMORY=$(docker stats --no-stream --format "{{.MemPerc}}" $service 2>/dev/null | sed 's/%//')
            CPU=$(docker stats --no-stream --format "{{.CPUPerc}}" $service 2>/dev/null | sed 's/%//')

            STATUS="healthy"
            if [ ! -z "$MEMORY" ] && (( $(echo "$MEMORY > 85" | bc -l) )); then STATUS="critical"; fi
            if [ ! -z "$CPU" ] && (( $(echo "$CPU > 80" | bc -l) )); then STATUS="warning"; fi

            generate_metric_html "$service Memory" "$MEMORY" "$STATUS" "%" >> "$DASHBOARD_FILE"
            generate_metric_html "$service CPU" "$CPU" "$STATUS" "%" >> "$DASHBOARD_FILE"
        else
            generate_metric_html "$service Status" "DOWN" "critical" "" >> "$DASHBOARD_FILE"
        fi
    done

    # Database metrics (if available)
    if docker ps --filter "name=postgres" --filter "status=running" | grep -q "postgres"; then
        CONNECTIONS=$(docker exec postgres psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null)
        generate_metric_html "DB Connections" "$CONNECTIONS" "healthy" "" >> "$DASHBOARD_FILE"
    fi

    echo "    </div>
    <div class='chart'>ðŸ“Š Real-time Charts Coming Soon</div>
</body>
</html>" >> "$DASHBOARD_FILE"

    echo "Dashboard generated: $DASHBOARD_FILE"
}

# Generate initial dashboard
generate_dashboard

echo "Performance dashboard is being served."
echo "Open $DASHBOARD_FILE in a web browser."
echo "Dashboard auto-refreshes every 30 seconds."
