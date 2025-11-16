#!/bin/bash

# Phase 5: Monitoring Integration Setup for Ubuntu Container
# This script creates comprehensive monitoring scripts for continuous system health checking

set -e

LOG_DIR="/var/log/localai"
MONITORING_DIR="$LOG_DIR/monitoring"
INTEGRATION_DIR="$MONITORING_DIR/integration"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Function to create comprehensive monitoring scripts
create_comprehensive_monitoring() {
    echo "Creating comprehensive monitoring integration script..."

    mkdir -p "$INTEGRATION_DIR"

    cat > "$INTEGRATION_DIR/comprehensive-monitoring.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
INTERVAL_MINUTES=5

echo "=== Comprehensive Monitoring Cycle - $TIMESTAMP ===" >> "$LOG_DIR/monitoring/integration.log"

# Run container monitoring
if [ -f "/var/log/localai/monitoring/container-monitor.sh" ]; then
    bash /var/log/localai/monitoring/container-monitor.sh >> "$LOG_DIR/monitoring/integration.log" 2>&1
fi

# Run health checks
if [ -f "/var/log/localai/monitoring/health-check.sh" ]; then
    bash /var/log/localai/monitoring/health-check.sh >> "$LOG_DIR/monitoring/integration.log" 2>&1
fi

# Check for recent alerts
RECENT_ALERTS=$(find "$LOG_DIR/alerts" -name "*.log" -newermt "$INTERVAL_MINUTES minutes ago" -exec cat {} \; 2>/dev/null | grep -E "CRITICAL|WARNING|ERROR|FATAL" | wc -l)

if [ "$RECENT_ALERTS" -gt 0 ]; then
    echo "Found $RECENT_ALERTS recent alerts, sending notifications..." >> "$LOG_DIR/monitoring/integration.log"

    # Send alert notifications
    if [ -f "/var/log/localai/monitoring/external/comprehensive-alerts.sh" ]; then
        bash /var/log/localai/monitoring/external/comprehensive-alerts.sh >> "$LOG_DIR/monitoring/integration.log" 2>&1
    fi
fi

# Generate status report
if [ -f "/var/log/localai/monitoring/generate-reports.sh" ]; then
    bash /var/log/localai/monitoring/generate-reports.sh >> "$LOG_DIR/monitoring/integration.log" 2>&1
fi

echo "Comprehensive monitoring cycle completed at $TIMESTAMP" >> "$LOG_DIR/monitoring/integration.log"
EOF

    chmod +x "$INTEGRATION_DIR/comprehensive-monitoring.sh"
    echo "Comprehensive monitoring script created."
}

# Function to create system status report generation
create_status_report_generation() {
    echo "Creating system status report generation..."

    cat > "$INTEGRATION_DIR/generate-status-report.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
REPORTS_DIR="$LOG_DIR/reports"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="$REPORTS_DIR/system-status-$TIMESTAMP.html"

mkdir -p "$REPORTS_DIR"

# Gather system information
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

# Get container status
if command -v docker &> /dev/null; then
    CONTAINER_STATUS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
else
    CONTAINER_STATUS="Docker not available"
fi

# Get recent alerts (last 24 hours)
RECENT_ALERTS=$(find "$LOG_DIR/alerts" -name "*.log" -newermt '24 hours ago' -exec tail -10 {} \; 2>/dev/null | head -20)

# Generate HTML report
cat > "$REPORT_FILE" << HTML_EOF
<!DOCTYPE html>
<html>
<head>
    <title>LocalAI System Status Report - $TIMESTAMP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .section { background: white; margin: 20px 0; padding: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric { display: flex; justify-content: space-between; padding: 10px; border-bottom: 1px solid #eee; }
        .metric:last-child { border-bottom: none; }
        .value { font-weight: bold; }
        .healthy { color: #27ae60; }
        .warning { color: #f39c12; }
        .critical { color: #e74c3c; }
        .container-status { font-family: monospace; white-space: pre; background: #f8f9fa; padding: 10px; border-radius: 3px; margin: 10px 0; }
        .alerts { background: #fff5f5; border-left: 4px solid #e74c3c; padding: 10px; margin: 10px 0; }
        pre { white-space: pre-wrap; }
    </style>
</head>
<body>
    <div class="header">
        <h1>LocalAI System Status Report</h1>
        <p>Generated: $TIMESTAMP</p>
    </div>

    <div class="section">
        <h2>System Resources</h2>
        <div class="metric">
            <span>CPU Usage:</span>
            <span class="value $CPU_CLASS">${CPU_USAGE}%</span>
        </div>
        <div class="metric">
            <span>Memory Usage:</span>
            <span class="value $MEMORY_CLASS">${MEMORY_USAGE}%</span>
        </div>
        <div class="metric">
            <span>Disk Usage:</span>
            <span class="value $DISK_CLASS">${DISK_USAGE}%</span>
        </div>
    </div>

    <div class="section">
        <h2>Container Status</h2>
        <div class="container-status">$CONTAINER_STATUS</div>
    </div>

    <div class="section">
        <h2>Recent Alerts (Last 24h)</h2>
        <div class="alerts">
            <pre>$RECENT_ALERTS</pre>
        </div>
    </div>

    <div class="section">
        <h2>Monitoring Status</h2>
        <div class="metric">
            <span>Monitoring Active:</span>
            <span class="value healthy">Yes</span>
        </div>
        <div class="metric">
            <span>Last Report:</span>
            <span class="value">$TIMESTAMP</span>
        </div>
    </div>
</body>
</html>
HTML_EOF

echo "System status report generated: $REPORT_FILE"
EOF

    chmod +x "$INTEGRATION_DIR/generate-status-report.sh"
    echo "Status report generation script created."
}

# Function to create alert notification system
create_alert_notification_system() {
    echo "Creating alert notification system..."

    cat > "$INTEGRATION_DIR/send-alert-notifications.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
EMAIL_RECIPIENTS=("admin@yourdomain.com")
SLACK_WEBHOOK_URL=""
SMS_GATEWAY=""
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check for recent alerts
CRITICAL_ALERTS=$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep -l "CRITICAL\|FATAL" {} \; | wc -l)
WARNING_ALERTS=$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep -l "WARNING\|ERROR" {} \; | grep -v CRITICAL | grep -v FATAL | wc -l)

if [ "$CRITICAL_ALERTS" -gt 0 ] || [ "$WARNING_ALERTS" -gt 0 ]; then
    SUBJECT="LocalAI System Alerts - $TIMESTAMP"
    BODY="LocalAI System Alert Notification

Critical Alerts: $CRITICAL_ALERTS
Warning Alerts: $WARNING_ALERTS

Recent Critical Issues:
$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep "CRITICAL\|FATAL" {} \; | head -10)

Recent Warning Issues:
$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep "WARNING\|ERROR" {} \; | grep -v CRITICAL | grep -v FATAL | head -10)

Time: $TIMESTAMP"

    # Send email notifications
    for email in "${EMAIL_RECIPIENTS[@]}"; do
        echo "$BODY" | mail -s "$SUBJECT" "$email"
    done

    # Send Slack notification if configured
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$SUBJECT\",\"attachments\":[{\"color\":\"danger\",\"text\":\"$BODY\"}]}" \
            "$SLACK_WEBHOOK_URL"
    fi

    # Send SMS if configured
    if [ -n "$SMS_GATEWAY" ]; then
        SMS_BODY="LocalAI Alert: $CRITICAL_ALERTS critical, $WARNING_ALERTS warnings"
        echo "$SMS_BODY" | mail -s "Alert" "$SMS_GATEWAY"
    fi

    # Log notification
    echo "$TIMESTAMP - Notifications sent: Email(${#EMAIL_RECIPIENTS[@]})" >> "$LOG_DIR/alerts/notifications.log"
    echo "Alert notifications sent."
fi
EOF

    chmod +x "$INTEGRATION_DIR/send-alert-notifications.sh"
    echo "Alert notification system created."
}

# Function to create monitoring dashboard creation
create_monitoring_dashboard() {
    echo "Creating monitoring dashboard creation script..."

    cat > "$INTEGRATION_DIR/create-monitoring-dashboard.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
DASHBOARD_FILE="$LOG_DIR/grafana-dashboard.json"

# Create Grafana dashboard JSON
cat > "$DASHBOARD_FILE" << 'DASHBOARD_EOF'
{
  "dashboard": {
    "title": "LocalAI Comprehensive Monitoring",
    "tags": ["localai", "monitoring", "comprehensive"],
    "timezone": "browser",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
        "targets": [
          {
            "expr": "100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)",
            "legendFormat": "Memory Usage %"
          }
        ]
      },
      {
        "title": "Disk Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
        "targets": [
          {
            "expr": "(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100",
            "legendFormat": "{{mountpoint}} Disk Usage %"
          }
        ]
      },
      {
        "title": "Container CPU Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total[5m]) * 100",
            "legendFormat": "{{name}} CPU %"
          }
        ]
      },
      {
        "title": "Container Memory Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 16 },
        "targets": [
          {
            "expr": "container_memory_usage_bytes / container_memory_limit_bytes * 100",
            "legendFormat": "{{name}} Memory %"
          }
        ]
      },
      {
        "title": "Service Uptime",
        "type": "table",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 16 },
        "targets": [
          {
            "expr": "up",
            "legendFormat": "{{job}}"
          }
        ]
      }
    ],
    "time": { "from": "now-1h", "to": "now" },
    "refresh": "5m"
  }
}
DASHBOARD_EOF

echo "Grafana dashboard JSON created: $DASHBOARD_FILE"
echo "Import this file into Grafana to create the monitoring dashboard."
EOF

    chmod +x "$INTEGRATION_DIR/create-monitoring-dashboard.sh"
    echo "Monitoring dashboard creation script created."
}

# Function to set up cron jobs for monitoring integration
setup_cron_monitoring_integration() {
    echo "Setting up cron jobs for monitoring integration..."

    # Comprehensive monitoring every 5 minutes
    (crontab -l 2>/dev/null; echo "*/5 * * * * $INTEGRATION_DIR/comprehensive-monitoring.sh") | crontab -

    # Status report generation hourly
    (crontab -l 2>/dev/null; echo "0 * * * * $INTEGRATION_DIR/generate-status-report.sh") | crontab -

    # Alert notifications every 15 minutes
    (crontab -l 2>/dev/null; echo "*/15 * * * * $INTEGRATION_DIR/send-alert-notifications.sh") | crontab -

    echo "Cron monitoring integration jobs configured."
}

# Main execution
case "$1" in
    "setup")
        mkdir -p "$INTEGRATION_DIR"
        create_comprehensive_monitoring
        create_status_report_generation
        create_alert_notification_system
        create_monitoring_dashboard
        setup_cron_monitoring_integration
        ;;
    "monitor")
        "$INTEGRATION_DIR/comprehensive-monitoring.sh"
        ;;
    "report")
        "$INTEGRATION_DIR/generate-status-report.sh"
        ;;
    "alerts")
        "$INTEGRATION_DIR/send-alert-notifications.sh"
        ;;
    "dashboard")
        "$INTEGRATION_DIR/create-monitoring-dashboard.sh"
        ;;
    *)
        echo "Usage: $0 {setup|monitor|report|alerts|dashboard}"
        echo "  setup     - Full monitoring integration setup"
        echo "  monitor   - Run comprehensive monitoring manually"
        echo "  report    - Generate status report manually"
        echo "  alerts    - Send alert notifications manually"
        echo "  dashboard - Create monitoring dashboard JSON"
        exit 1
        ;;
esac

echo "Monitoring integration setup completed for Ubuntu container."
EOF

    chmod +x "$INTEGRATION_DIR/generate-status-report.sh"
    echo "Status report generation script created."
}

# Function to create alert notification system
create_alert_notification_system() {
    echo "Creating alert notification system..."

    cat > "$INTEGRATION_DIR/send-alert-notifications.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
EMAIL_RECIPIENTS=("admin@yourdomain.com")
SLACK_WEBHOOK_URL=""
SMS_GATEWAY=""
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check for recent alerts
CRITICAL_ALERTS=$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep -l "CRITICAL\|FATAL" {} \; | wc -l)
WARNING_ALERTS=$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep -l "WARNING\|ERROR" {} \; | grep -v CRITICAL | grep -v FATAL | wc -l)

if [ "$CRITICAL_ALERTS" -gt 0 ] || [ "$WARNING_ALERTS" -gt 0 ]; then
    SUBJECT="LocalAI System Alerts - $TIMESTAMP"
    BODY="LocalAI System Alert Notification

Critical Alerts: $CRITICAL_ALERTS
Warning Alerts: $WARNING_ALERTS

Recent Critical Issues:
$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep "CRITICAL\|FATAL" {} \; | head -10)

Recent Warning Issues:
$(find "$LOG_DIR/alerts" -name "*.log" -newermt '15 minutes ago' -exec grep "WARNING\|ERROR" {} \; | grep -v CRITICAL | grep -v FATAL | head -10)

Time: $TIMESTAMP"

    # Send email notifications
    for email in "${EMAIL_RECIPIENTS[@]}"; do
        echo "$BODY" | mail -s "$SUBJECT" "$email"
    done

    # Send Slack notification if configured
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$SUBJECT\",\"attachments\":[{\"color\":\"danger\",\"text\":\"$BODY\"}]}" \
            "$SLACK_WEBHOOK_URL"
    fi

    # Send SMS if configured
    if [ -n "$SMS_GATEWAY" ]; then
        SMS_BODY="LocalAI Alert: $CRITICAL_ALERTS critical, $WARNING_ALERTS warnings"
        echo "$SMS_BODY" | mail -s "Alert" "$SMS_GATEWAY"
    fi

    # Log notification
    echo "$TIMESTAMP - Notifications sent: Email(${#EMAIL_RECIPIENTS[@]})" >> "$LOG_DIR/alerts/notifications.log"
    echo "Alert notifications sent."
fi
EOF

    chmod +x "$INTEGRATION_DIR/send-alert-notifications.sh"
    echo "Alert notification system created."
}

# Function to create monitoring dashboard creation
create_monitoring_dashboard() {
    echo "Creating monitoring dashboard creation script..."

    cat > "$INTEGRATION_DIR/create-monitoring-dashboard.sh" << 'EOF'
#!/bin/bash

LOG_DIR="/var/log/localai"
DASHBOARD_FILE="$LOG_DIR/grafana-dashboard.json"

# Create Grafana dashboard JSON
cat > "$DASHBOARD_FILE" << 'DASHBOARD_EOF'
{
  "dashboard": {
    "title": "LocalAI Comprehensive Monitoring",
    "tags": ["localai", "monitoring", "comprehensive"],
    "timezone": "browser",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "targets": [
          {
            "expr": "100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
        "targets": [
          {
            "expr": "100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)",
            "legendFormat": "Memory Usage %"
          }
        ]
      },
      {
        "title": "Disk Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
        "targets": [
          {
            "expr": "(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100",
            "legendFormat": "{{mountpoint}} Disk Usage %"
          }
        ]
      },
      {
        "title": "Container CPU Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total[5m]) * 100",
            "legendFormat": "{{name}} CPU %"
          }
        ]
      },
      {
        "title": "Container Memory Usage",
        "type": "graph",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 16 },
        "targets": [
          {
            "expr": "container_memory_usage_bytes / container_memory_limit_bytes * 100",
            "legendFormat": "{{name}} Memory %"
          }
        ]
      },
      {
        "title": "Service Uptime",
        "type": "table",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 16 },
        "targets": [
          {
            "expr": "up",
            "legendFormat": "{{job}}"
          }
        ]
      }
    ],
    "time": { "from": "now-1h", "to": "now" },
    "refresh": "5m"
  }
}
DASHBOARD_EOF

echo "Grafana dashboard JSON created: $DASHBOARD_FILE"
echo "Import this file into Grafana to create the monitoring dashboard."
EOF

    chmod +x "$INTEGRATION_DIR/create-monitoring-dashboard.sh"
    echo "Monitoring dashboard creation script created."
}

# Function to set up cron jobs for monitoring integration
setup_cron_monitoring_integration() {
    echo "Setting up cron jobs for monitoring integration..."

    # Comprehensive monitoring every 5 minutes
    (crontab -l 2>/dev/null; echo "*/5 * * * * $INTEGRATION_DIR/comprehensive-monitoring.sh") | crontab -

    # Status report generation hourly
    (crontab -l 2>/dev/null; echo "0 * * * * $INTEGRATION_DIR/generate-status-report.sh") | crontab -

    # Alert notifications every 15 minutes
    (crontab -l 2>/dev/null; echo "*/15 * * * * $INTEGRATION_DIR/send-alert-notifications.sh") | crontab -

    echo "Cron monitoring integration jobs configured."
}

# Main execution
case "$1" in
    "setup")
        mkdir -p "$INTEGRATION_DIR"
        create_comprehensive_monitoring
        create_status_report_generation
        create_alert_notification_system
        create_monitoring_dashboard
        setup_cron_monitoring_integration
        ;;
    "monitor")
        "$INTEGRATION_DIR/comprehensive-monitoring.sh"
        ;;
    "report")
        "$INTEGRATION_DIR/generate-status-report.sh"
        ;;
    "alerts")
        "$INTEGRATION_DIR/send-alert-notifications.sh"
        ;;
    "dashboard")
        "$INTEGRATION_DIR/create-monitoring-dashboard.sh"
        ;;
    *)
        echo "Usage: $0 {setup|monitor|report|alerts|dashboard}"
        echo "  setup     - Full monitoring integration setup"
        echo "  monitor   - Run comprehensive monitoring manually"
        echo "  report    - Generate status report manually"
        echo "  alerts    - Send alert notifications manually"
        echo "  dashboard - Create monitoring dashboard JSON"
        exit 1
        ;;
esac

echo "Monitoring integration setup completed for Ubuntu container."