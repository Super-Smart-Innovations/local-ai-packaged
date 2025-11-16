#!/bin/bash

# Phase 5: Health Checks and Alerts Setup for Ubuntu Container
# This script implements comprehensive health monitoring and alerting inside the container

set -e

LOG_DIR="/var/log/localai"
ALERTS_DIR="$LOG_DIR/alerts"
MONITORING_DIR="$LOG_DIR/monitoring"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Function to create Docker health checks configuration
create_docker_health_checks() {
    echo "Creating Docker health checks configuration..."

    # Create health check script for each service
    cat > "$MONITORING_DIR/health-check.sh" << 'EOF'
#!/bin/bash

# Health check functions for each service

check_n8n() {
    if curl -f -s http://localhost:5678/healthz > /dev/null 2>&1; then
        echo "n8n: HEALTHY"
        return 0
    else
        echo "n8n: UNHEALTHY"
        return 1
    fi
}

check_supabase() {
    if curl -f -s http://localhost:54321/rest/v1/ > /dev/null 2>&1; then
        echo "supabase: HEALTHY"
        return 0
    else
        echo "supabase: UNHEALTHY"
        return 1
    fi
}

check_ollama() {
    if ollama list > /dev/null 2>&1; then
        echo "ollama: HEALTHY"
        return 0
    else
        echo "ollama: UNHEALTHY"
        return 1
    fi
}

check_openwebui() {
    if curl -f -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "openwebui: HEALTHY"
        return 0
    else
        echo "openwebui: UNHEALTHY"
        return 1
    fi
}

check_qdrant() {
    if curl -f -s http://localhost:6333/health > /dev/null 2>&1; then
        echo "qdrant: HEALTHY"
        return 0
    else
        echo "qdrant: UNHEALTHY"
        return 1
    fi
}

check_neo4j() {
    if curl -f -s http://localhost:7474/ > /dev/null 2>&1; then
        echo "neo4j: HEALTHY"
        return 0
    else
        echo "neo4j: UNHEALTHY"
        return 1
    fi
}

# Run all health checks
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="/var/log/localai/monitoring/health-checks.log"

echo "=== Health Check Report - $TIMESTAMP ===" >> "$LOG_FILE"

SERVICES=("n8n" "supabase" "ollama" "openwebui" "qdrant" "neo4j")
FAILED_SERVICES=()

for service in "${SERVICES[@]}"; do
    if check_"$service" >> "$LOG_FILE" 2>&1; then
        echo "✓ $service is healthy" >> "$LOG_FILE"
    else
        echo "✗ $service is unhealthy" >> "$LOG_FILE"
        FAILED_SERVICES+=("$service")
    fi
done

# Alert if any services are unhealthy
if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    ALERT_FILE="/var/log/localai/alerts/health-alerts.log"
    echo "$TIMESTAMP - CRITICAL: Unhealthy services: ${FAILED_SERVICES[*]}" >> "$ALERT_FILE"
    echo "ALERT: ${#FAILED_SERVICES[@]} services are unhealthy!"
fi

echo "Health checks completed."
EOF

    chmod +x "$MONITORING_DIR/health-check.sh"
    echo "Health check script created."
}

# Function to create resource monitoring alerts
create_resource_monitoring() {
    echo "Creating resource monitoring and alerts..."

    cat > "$MONITORING_DIR/resource-monitor.sh" << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/localai/monitoring/resources.log"
ALERT_FILE="/var/log/localai/alerts/resource-alerts.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=90

echo "=== Resource Monitoring - $TIMESTAMP ===" >> "$LOG_FILE"

# Check CPU usage
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
echo "CPU Usage: ${CPU_USAGE}%" >> "$LOG_FILE"

if (( $(echo "$CPU_USAGE > $CPU_THRESHOLD" | bc -l) )); then
    echo "$TIMESTAMP - ALERT: High CPU usage: ${CPU_USAGE}%" >> "$ALERT_FILE"
    echo "ALERT: CPU usage above threshold!"
fi

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
echo "Memory Usage: ${MEMORY_USAGE}%" >> "$LOG_FILE"

if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
    echo "$TIMESTAMP - ALERT: High memory usage: ${MEMORY_USAGE}%" >> "$ALERT_FILE"
    echo "ALERT: Memory usage above threshold!"
fi

# Check disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
echo "Disk Usage: ${DISK_USAGE}%" >> "$LOG_FILE"

if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    echo "$TIMESTAMP - ALERT: High disk usage: ${DISK_USAGE}%" >> "$ALERT_FILE"
    echo "ALERT: Disk usage above threshold!"
fi

# Check container resources if Docker is available
if command -v docker &> /dev/null; then
    echo "=== Container Resources ===" >> "$LOG_FILE"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" >> "$LOG_FILE"
fi

echo "Resource monitoring completed."
EOF

    chmod +x "$MONITORING_DIR/resource-monitor.sh"
    echo "Resource monitoring script created."
}

# Function to create uptime monitoring
create_uptime_monitoring() {
    echo "Creating uptime monitoring..."

    cat > "$MONITORING_DIR/uptime-monitor.sh" << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/localai/monitoring/uptime.log"
ALERT_FILE="/var/log/localai/alerts/uptime-alerts.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Services to monitor
SERVICES=(
    "http://localhost:5678 n8n"
    "http://localhost:3000 openwebui"
    "http://localhost:3001 flowise"
    "http://localhost:6333 qdrant"
    "http://localhost:7474 neo4j"
    "http://localhost:54321 supabase"
)

echo "=== Uptime Monitoring - $TIMESTAMP ===" >> "$LOG_FILE"
FAILED_SERVICES=()

for service in "${SERVICES[@]}"; do
    URL=$(echo "$service" | awk '{print $1}')
    NAME=$(echo "$service" | awk '{print $2}')

    if curl -f -s --max-time 10 "$URL" > /dev/null 2>&1; then
        echo "✓ $NAME ($URL) is UP" >> "$LOG_FILE"
    else
        echo "✗ $NAME ($URL) is DOWN" >> "$LOG_FILE"
        FAILED_SERVICES+=("$NAME")
        echo "$TIMESTAMP - ALERT: $NAME ($URL) is DOWN" >> "$ALERT_FILE"
    fi
done

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo "ALERT: ${#FAILED_SERVICES[@]} services are down: ${FAILED_SERVICES[*]}"
fi

echo "Uptime monitoring completed."
EOF

    chmod +x "$MONITORING_DIR/uptime-monitor.sh"
    echo "Uptime monitoring script created."
}

# Function to create SSL certificate monitoring
create_ssl_monitoring() {
    echo "Creating SSL certificate monitoring..."

    cat > "$MONITORING_DIR/ssl-monitor.sh" << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/localai/monitoring/ssl.log"
ALERT_FILE="/var/log/localai/alerts/ssl-alerts.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
WARNING_DAYS=30

# Domains to monitor (customize as needed)
DOMAINS=(
    "localhost"
    # Add your actual domains here
    # "yourdomain.com"
    # "api.yourdomain.com"
)

echo "=== SSL Certificate Monitoring - $TIMESTAMP ===" >> "$LOG_FILE"

for domain in "${DOMAINS[@]}"; do
    if echo | openssl s_client -servername "$domain" -connect "$domain":443 2>/dev/null | openssl x509 -noout -dates > /dev/null 2>&1; then
        EXPIRY_DATE=$(echo | openssl s_client -servername "$domain" -connect "$domain":443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
        EXPIRY_SECONDS=$(date -d "$EXPIRY_DATE" +%s)
        CURRENT_SECONDS=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_SECONDS - CURRENT_SECONDS) / 86400 ))

        echo "$domain expires in $DAYS_LEFT days ($EXPIRY_DATE)" >> "$LOG_FILE"

        if [ "$DAYS_LEFT" -le "$WARNING_DAYS" ]; then
            echo "$TIMESTAMP - ALERT: SSL certificate for $domain expires in $DAYS_LEFT days" >> "$ALERT_FILE"
            echo "ALERT: SSL certificate for $domain expires soon!"
        fi
    else
        echo "$domain: No SSL certificate or connection failed" >> "$LOG_FILE"
        echo "$TIMESTAMP - ERROR: Cannot check SSL certificate for $domain" >> "$ALERT_FILE"
    fi
done

echo "SSL monitoring completed."
EOF

    chmod +x "$MONITORING_DIR/ssl-monitor.sh"
    echo "SSL monitoring script created."
}

# Function to create alerting system
create_alerting_system() {
    echo "Creating alerting system..."

    cat > "$MONITORING_DIR/alert-system.sh" << 'EOF'
#!/bin/bash

ALERTS_DIR="/var/log/localai/alerts"
LOG_FILE="/var/log/localai/monitoring/alerts.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "=== Alert System Check - $TIMESTAMP ===" >> "$LOG_FILE"

# Check for new alerts
NEW_ALERTS=$(find "$ALERTS_DIR" -name "*.log" -newermt '1 hour ago' -exec grep -l "ALERT\|CRITICAL\|ERROR" {} \; 2>/dev/null | wc -l)

if [ "$NEW_ALERTS" -gt 0 ]; then
    echo "Found $NEW_ALERTS alert files with recent alerts" >> "$LOG_FILE"

    # Here you can add email/SMS notifications
    # Example: send email alert
    # mail -s "LocalAI System Alerts" your-email@example.com < <(find "$ALERTS_DIR" -name "*.log" -newermt '1 hour ago' -exec cat {} \;)

    # For now, just log the alert summary
    ALERT_SUMMARY=$(find "$ALERTS_DIR" -name "*.log" -newermt '1 hour ago' -exec tail -5 {} \; | grep -E "ALERT|CRITICAL|ERROR" | tail -10)
    if [ -n "$ALERT_SUMMARY" ]; then
        echo "Recent alerts summary:" >> "$LOG_FILE"
        echo "$ALERT_SUMMARY" >> "$LOG_FILE"
    fi
else
    echo "No new alerts found" >> "$LOG_FILE"
fi

echo "Alert system check completed."
EOF

    chmod +x "$MONITORING_DIR/alert-system.sh"
    echo "Alerting system script created."
}

# Function to set up cron jobs for monitoring
setup_cron_monitoring() {
    echo "Setting up cron jobs for monitoring..."

    # Health checks every 5 minutes
    (crontab -l 2>/dev/null; echo "*/5 * * * * $MONITORING_DIR/health-check.sh") | crontab -

    # Resource monitoring every 10 minutes
    (crontab -l 2>/dev/null; echo "*/10 * * * * $MONITORING_DIR/resource-monitor.sh") | crontab -

    # Uptime monitoring every 5 minutes
    (crontab -l 2>/dev/null; echo "*/5 * * * * $MONITORING_DIR/uptime-monitor.sh") | crontab -

    # SSL monitoring daily at 6 AM
    (crontab -l 2>/dev/null; echo "0 6 * * * $MONITORING_DIR/ssl-monitor.sh") | crontab -

    # Alert system check hourly
    (crontab -l 2>/dev/null; echo "0 * * * * $MONITORING_DIR/alert-system.sh") | crontab -

    echo "Cron monitoring jobs configured."
}

# Function to install monitoring tools
install_monitoring_tools() {
    echo "Installing monitoring tools..."

    apt-get update -qq

    # Install required tools
    apt-get install -y \
        curl \
        bc \
        openssl \
        cron \
        mailutils \
        ssmtp

    echo "Monitoring tools installed."
}

# Main execution
case "$1" in
    "install")
        install_monitoring_tools
        mkdir -p "$ALERTS_DIR" "$MONITORING_DIR"
        ;;
    "setup")
        mkdir -p "$ALERTS_DIR" "$MONITORING_DIR"
        create_docker_health_checks
        create_resource_monitoring
        create_uptime_monitoring
        create_ssl_monitoring
        create_alerting_system
        setup_cron_monitoring
        ;;
    "health")
        "$MONITORING_DIR/health-check.sh"
        ;;
    "resources")
        "$MONITORING_DIR/resource-monitor.sh"
        ;;
    "uptime")
        "$MONITORING_DIR/uptime-monitor.sh"
        ;;
    "ssl")
        "$MONITORING_DIR/ssl-monitor.sh"
        ;;
    "alerts")
        "$MONITORING_DIR/alert-system.sh"
        ;;
    *)
        echo "Usage: $0 {install|setup|health|resources|uptime|ssl|alerts}"
        echo "  install   - Install monitoring tools and create directories"
        echo "  setup     - Full setup with all monitoring and alerting"
        echo "  health    - Run health checks manually"
        echo "  resources - Run resource monitoring manually"
        echo "  uptime    - Run uptime monitoring manually"
        echo "  ssl       - Run SSL monitoring manually"
        echo "  alerts    - Check alerts manually"
        exit 1
        ;;
esac

echo "Health checks and alerts setup completed for Ubuntu container."