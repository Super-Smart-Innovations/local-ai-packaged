#!/bin/bash

# Phase 5: Log Aggregation Setup for Ubuntu Container
# This script configures comprehensive logging inside the Ubuntu container

set -e

BASE_LOG_DIR="/var/log/localai"
SERVICES_LOG_DIR="$BASE_LOG_DIR/services"
RETENTION_DAYS=30
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Function to create log directory structure
create_log_structure() {
    echo "Creating log directory structure..."

    mkdir -p "$SERVICES_LOG_DIR"/{n8n,supabase,ollama,qdrant,neo4j,langfuse,searxng,flowise,openwebui}
    mkdir -p "$BASE_LOG_DIR"/{security,system,monitoring,backups,alerts,performance}

    echo "Log directory structure created."
}

# Function to configure logrotate for Docker logs
configure_logrotate() {
    echo "Configuring logrotate for Docker logs..."

    cat > /etc/logrotate.d/docker-services << EOF
/var/log/localai/services/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 root root
    postrotate
        docker-compose -f /path/to/docker-compose.yml logs -f --tail=100 > /dev/null 2>&1 || true
    endscript
}

/var/log/localai/monitoring/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    create 0644 root root
}
EOF

    echo "Logrotate configuration created."
}

# Function to set up systemd journal configuration
configure_systemd_journal() {
    echo "Configuring systemd journal for persistent logging..."

    # Create journald configuration
    cat > /etc/systemd/journald.conf << EOF
[Journal]
Storage=persistent
Compress=yes
Seal=no
SplitMode=uid
SyncIntervalSec=5m
RateLimitInterval=30s
RateLimitBurst=1000
MaxRetentionSec=30day
MaxFileSec=1week
EOF

    systemctl restart systemd-journald
    echo "Systemd journal configured."
}

# Function to create log aggregation script
create_log_aggregation_script() {
    echo "Creating log aggregation script..."

    cat > "$BASE_LOG_DIR/log-aggregation.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
AGGREGATION_LOG="$LOG_DIR/aggregation-$TIMESTAMP.log"

echo "=== Log Aggregation Report - $TIMESTAMP ===" > "$AGGREGATION_LOG"

# Aggregate service logs
echo -e "\n=== Service Logs Summary ===" >> "$AGGREGATION_LOG"
for service_dir in "$LOG_DIR/services"/*/; do
    if [ -d "$service_dir" ]; then
        service_name=$(basename "$service_dir")
        log_count=$(find "$service_dir" -name "*.log" -type f 2>/dev/null | wc -l)
        total_size=$(du -sh "$service_dir" 2>/dev/null | cut -f1)
        echo "$service_name: $log_count files, $total_size" >> "$AGGREGATION_LOG"
    fi
done

# Check for error patterns
echo -e "\n=== Error Summary (Last 24h) ===" >> "$AGGREGATION_LOG"
find "$LOG_DIR" -name "*.log" -type f -mtime -1 -exec grep -l "ERROR\|CRITICAL\|FATAL" {} \; 2>/dev/null | while read -r file; do
    error_count=$(grep -c "ERROR\|CRITICAL\|FATAL" "$file" 2>/dev/null || echo "0")
    echo "$(basename "$file"): $error_count errors" >> "$AGGREGATION_LOG"
done

# System resource logs
echo -e "\n=== System Resources ===" >> "$AGGREGATION_LOG"
df -h / >> "$AGGREGATION_LOG"
free -h >> "$AGGREGATION_LOG"
uptime >> "$AGGREGATION_LOG"

echo "Log aggregation completed: $AGGREGATION_LOG"
EOF

    chmod +x "$BASE_LOG_DIR/log-aggregation.sh"
    echo "Log aggregation script created."
}

# Function to set up log cleanup cron job
setup_log_cleanup_cron() {
    echo "Setting up log cleanup cron job..."

    # Create cleanup script
    cat > "$BASE_LOG_DIR/log-cleanup.sh" << EOF
#!/bin/bash

LOG_DIR="/var/log/localai"
RETENTION_DAYS=$RETENTION_DAYS

echo "Starting log cleanup (retention: \$RETENTION_DAYS days)..."

# Find and remove old log files
find "\$LOG_DIR" -name "*.log" -type f -mtime +\$RETENTION_DAYS -exec rm -f {} \;

# Find and remove old compressed logs
find "\$LOG_DIR" -name "*.log.*.gz" -type f -mtime +\$((RETENTION_DAYS * 2)) -exec rm -f {} \;

echo "Log cleanup completed."
EOF

    chmod +x "$BASE_LOG_DIR/log-cleanup.sh"

    # Add to cron (daily at 3 AM)
    cron_job="0 3 * * * $BASE_LOG_DIR/log-cleanup.sh"
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

    echo "Log cleanup cron job configured."
}

# Function to create log monitoring and alerting script
create_log_monitoring_script() {
    echo "Creating log monitoring and alerting script..."

    cat > "$BASE_LOG_DIR/log-monitor.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
ALERT_LOG="$LOG_DIR/alerts/alerts.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Function to check for critical errors
check_critical_errors() {
    echo "Checking for critical errors..."

    # Define error patterns to monitor
    error_patterns=("FATAL" "CRITICAL" "PANIC" "Exception" "Segmentation fault")

    for pattern in "${error_patterns[@]}"; do
        error_files=$(find "$LOG_DIR" -name "*.log" -type f -mtime -1 -exec grep -l "$pattern" {} \; 2>/dev/null)
        if [ -n "$error_files" ]; then
            echo "[$TIMESTAMP] CRITICAL: Found '$pattern' in logs:" >> "$ALERT_LOG"
            echo "$error_files" >> "$ALERT_LOG"
            # Here you could add email/SMS alerts
            echo "ALERT: Critical error pattern '$pattern' detected!"
        fi
    done
}

# Function to monitor log file sizes
check_log_sizes() {
    echo "Checking log file sizes..."

    find "$LOG_DIR" -name "*.log" -type f -size +100M -exec ls -lh {} \; | while read -r line; do
        echo "[$TIMESTAMP] WARNING: Large log file detected:" >> "$ALERT_LOG"
        echo "$line" >> "$ALERT_LOG"
    done
}

# Function to check for service availability logs
check_service_availability() {
    echo "Checking service availability..."

    # Check if services are logging (indicating they're running)
    services=("n8n" "supabase" "ollama" "qdrant" "neo4j" "langfuse" "searxng" "flowise" "openwebui")

    for service in "${services[@]}"; do
        service_log_dir="$LOG_DIR/services/$service"
        if [ -d "$service_log_dir" ]; then
            recent_logs=$(find "$service_log_dir" -name "*.log" -type f -mmin -60 2>/dev/null | wc -l)
            if [ "$recent_logs" -eq 0 ]; then
                echo "[$TIMESTAMP] WARNING: No recent logs for service $service (possible service down)" >> "$ALERT_LOG"
            fi
        fi
    done
}

# Run all checks
check_critical_errors
check_log_sizes
check_service_availability

echo "Log monitoring completed."
EOF

    chmod +x "$BASE_LOG_DIR/log-monitor.sh"

    # Set up cron job for monitoring (every 15 minutes)
    monitor_cron="*/15 * * * * $BASE_LOG_DIR/log-monitor.sh"
    (crontab -l 2>/dev/null; echo "$monitor_cron") | crontab -

    echo "Log monitoring script created and scheduled."
}

# Function to install log analysis tools
install_log_tools() {
    echo "Installing log analysis tools..."

    apt-get update -qq

    # Install log analysis tools
    apt-get install -y \
        logrotate \
        rsyslog \
        syslog-ng \
        lnav \
        multitail \
        logwatch

    echo "Log analysis tools installed."
}

# Main execution
case "$1" in
    "install")
        install_log_tools
        create_log_structure
        configure_logrotate
        configure_systemd_journal
        ;;
    "setup")
        create_log_structure
        configure_logrotate
        configure_systemd_journal
        create_log_aggregation_script
        setup_log_cleanup_cron
        create_log_monitoring_script
        ;;
    "cleanup")
        "$BASE_LOG_DIR/log-cleanup.sh"
        ;;
    "monitor")
        "$BASE_LOG_DIR/log-monitor.sh"
        ;;
    "aggregate")
        "$BASE_LOG_DIR/log-aggregation.sh"
        ;;
    *)
        echo "Usage: $0 {install|setup|cleanup|monitor|aggregate}"
        echo "  install   - Install log tools and basic configuration"
        echo "  setup     - Full setup with aggregation, cleanup, and monitoring"
        echo "  cleanup   - Run manual log cleanup"
        echo "  monitor   - Run manual log monitoring"
        "  aggregate - Run manual log aggregation"
        exit 1
        ;;
esac

echo "Log aggregation setup completed for Ubuntu container."