#!/bin/bash

# Phase 5: External Monitoring Services Setup for Ubuntu Container
# This script configures external monitoring services inside the container

set -e

MONITORING_DIR="/var/log/localai/monitoring"
EXTERNAL_DIR="$MONITORING_DIR/external"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Function to install external monitoring tools
install_external_tools() {
    echo "Installing external monitoring tools..."

    apt-get update -qq

    # Install monitoring and alerting tools
    apt-get install -y \
        curl \
        wget \
        jq \
        mailutils \
        ssmtp \
        prometheus \
        grafana \
        elasticsearch \
        logstash \
        kibana

    echo "External monitoring tools installed."
}

# Function to configure UptimeRobot API integration
configure_uptimerobot_api() {
    echo "Configuring UptimeRobot API integration..."

    cat > "$EXTERNAL_DIR/uptimerobot-monitor.sh" << 'EOF'
#!/bin/bash

# UptimeRobot API Configuration
API_KEY="your-uptimerobot-api-key"
MONITOR_URLS=(
    "https://yourdomain.com"
    "https://n8n.yourdomain.com"
    "https://webui.yourdomain.com"
    "https://api.yourdomain.com"
)

LOG_FILE="/var/log/localai/monitoring/uptimerobot.log"

for url in "${MONITOR_URLS[@]}"; do
    # Use UptimeRobot API to create/update monitors
    # Note: Replace with actual API calls when you have the API key
    echo "$(date) - Would create UptimeRobot monitor for: $url" >> "$LOG_FILE"
done

echo "UptimeRobot API integration configured."
EOF

    chmod +x "$EXTERNAL_DIR/uptimerobot-monitor.sh"
    echo "UptimeRobot API integration script created."
}

# Function to set up email/SMS alerting
configure_alerting() {
    echo "Configuring email/SMS alerting..."

    # Configure ssmtp for email alerts
    cat > /etc/ssmtp/ssmtp.conf << EOF
root=alerts@yourdomain.com
mailhub=smtp.gmail.com:587
AuthUser=your-email@gmail.com
AuthPass=your-app-password
UseSTARTTLS=YES
EOF

    cat > /etc/ssmtp/revaliases << EOF
root:alerts@yourdomain.com:smtp.gmail.com:587
EOF

    # Create SMS alerting script (using email to SMS gateway)
    cat > "$EXTERNAL_DIR/sms-alert.sh" << 'EOF'
#!/bin/bash

# SMS Alerting via Email to SMS Gateway
# Configure your SMS gateway email address

SMS_GATEWAY="your-number@tmomail.net"  # Example for T-Mobile
# SMS_GATEWAY="your-number@vtext.com"  # Verizon
# SMS_GATEWAY="your-number@txt.att.net"  # AT&T

MESSAGE="$1"

if [ -n "$MESSAGE" ]; then
    echo "$MESSAGE" | mail -s "LocalAI Alert" "$SMS_GATEWAY"
    echo "$(date) - SMS alert sent: $MESSAGE" >> "/var/log/localai/alerts/sms.log"
fi
EOF

    chmod +x "$EXTERNAL_DIR/sms-alert.sh"

    # Create comprehensive alerting script
    cat > "$EXTERNAL_DIR/comprehensive-alerts.sh" << 'EOF'
#!/bin/bash

ALERTS_DIR="/var/log/localai/alerts"
EMAIL_RECIPIENTS=("admin@yourdomain.com" "support@yourdomain.com")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check for critical alerts
CRITICAL_ALERTS=$(find "$ALERTS_DIR" -name "*.log" -newermt '1 hour ago' -exec grep -l "CRITICAL\|FATAL" {} \; 2>/dev/null | wc -l)
WARNING_ALERTS=$(find "$ALERTS_DIR" -name "*.log" -newermt '1 hour ago' -exec grep -l "WARNING\|ERROR" {} \; 2>/dev/null | wc -l)

if [ "$CRITICAL_ALERTS" -gt 0 ] || [ "$WARNING_ALERTS" -gt 0 ]; then
    SUBJECT="LocalAI System Alerts - $TIMESTAMP"
    BODY="Alert Summary:
- Critical Alerts: $CRITICAL_ALERTS
- Warning Alerts: $WARNING_ALERTS

Recent Alerts:
$(find "$ALERTS_DIR" -name "*.log" -newermt '1 hour ago' -exec tail -5 {} \; | grep -E "CRITICAL|FATAL|WARNING|ERROR" | tail -20)"

    # Send email alerts
    for email in "${EMAIL_RECIPIENTS[@]}"; do
        echo "$BODY" | mail -s "$SUBJECT" "$email"
    done

    # Send SMS alert for critical issues
    if [ "$CRITICAL_ALERTS" -gt 0 ]; then
        /var/log/localai/monitoring/external/sms-alert.sh "CRITICAL: $CRITICAL_ALERTS critical alerts detected in LocalAI system"
    fi

    echo "$TIMESTAMP - Alerts sent via email and SMS" >> "/var/log/localai/monitoring/alerts-sent.log"
fi
EOF

    chmod +x "$EXTERNAL_DIR/comprehensive-alerts.sh"
    echo "Comprehensive alerting system configured."
}

# Function to set up Slack integration
configure_slack_integration() {
    echo "Configuring Slack integration..."

    cat > "$EXTERNAL_DIR/slack-alert.sh" << 'EOF'
#!/bin/bash

# Slack Webhook Configuration
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"

MESSAGE="$1"
SEVERITY="${2:-info}"

# Set color based on severity
case "$SEVERITY" in
    "critical"|"error")
        COLOR="danger"
        ;;
    "warning")
        COLOR="warning"
        ;;
    *)
        COLOR="good"
        ;;
esac

# Send Slack notification
curl -X POST -H 'Content-type: application/json' \
    --data "{
        \"attachments\": [
            {
                \"color\": \"$COLOR\",
                \"title\": \"LocalAI System Alert\",
                \"text\": \"$MESSAGE\",
                \"footer\": \"LocalAI Monitoring\",
                \"ts\": $(date +%s)
            }
        ]
    }" "$SLACK_WEBHOOK_URL"

echo "$(date) - Slack alert sent: $MESSAGE" >> "/var/log/localai/alerts/slack.log"
EOF

    chmod +x "$EXTERNAL_DIR/slack-alert.sh"
    echo "Slack integration configured."
}

# Function to set up Grafana dashboards
configure_grafana_dashboards() {
    echo "Configuring Grafana dashboards..."

    # Create Grafana provisioning directory
    mkdir -p /etc/grafana/provisioning/dashboards

    # Create datasource configuration
    cat > /etc/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

    # Create dashboard provisioning
    cat > /etc/grafana/provisioning/dashboards/localai.yml << EOF
apiVersion: 1

providers:
  - name: 'LocalAI'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Create sample dashboard JSON
    cat > /var/lib/grafana/dashboards/localai-dashboard.json << 'EOF'
{
  "dashboard": {
    "title": "LocalAI System Monitoring",
    "tags": ["localai", "monitoring"],
    "timezone": "browser",
    "panels": [
      {
        "title": "CPU Usage",
        "type": "graph",
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
        "targets": [
          {
            "expr": "100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)",
            "legendFormat": "Memory Usage %"
          }
        ]
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    }
  }
}
EOF

    echo "Grafana dashboards configured."
}

# Function to configure ELK stack pipelines
configure_elk_pipelines() {
    echo "Configuring ELK stack pipelines..."

    # Create Logstash pipeline for LocalAI logs
    mkdir -p /etc/logstash/conf.d

    cat > /etc/logstash/conf.d/localai.conf << 'EOF'
input {
  file {
    path => "/var/log/localai/**/*.log"
    start_position => "beginning"
    sincedb_path => "/var/lib/logstash/sincedb"
    type => "localai_logs"
  }
}

filter {
  if [type] == "localai_logs" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} \[%{LOGLEVEL:level}\] %{DATA:source}: %{GREEDYDATA:message}" }
    }
    date {
      match => [ "timestamp", "ISO8601" ]
    }
  }
}

output {
  elasticsearch {
    hosts => ["localhost:9200"]
    index => "localai-logs-%{+YYYY.MM.dd}"
  }
  stdout { codec => rubydebug }
}
EOF

    # Create Kibana index pattern
    cat > "$EXTERNAL_DIR/create-kibana-index.sh" << 'EOF'
#!/bin/bash

# Wait for Elasticsearch to be ready
until curl -s http://localhost:9200/_cluster/health | grep -q '"status":"green"\|"status":"yellow"'; do
  echo "Waiting for Elasticsearch..."
  sleep 10
done

# Create index pattern
curl -X POST "http://localhost:5601/api/saved_objects/index-pattern/localai-logs" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d '{
    "attributes": {
      "title": "localai-logs-*",
      "timeFieldName": "@timestamp"
    }
  }'
EOF

    chmod +x "$EXTERNAL_DIR/create-kibana-index.sh"
    echo "ELK stack pipelines configured."
}

# Function to set up automated report generation
configure_automated_reports() {
    echo "Configuring automated report generation..."

    cat > "$EXTERNAL_DIR/generate-reports.sh" << 'EOF'
#!/bin/bash

REPORTS_DIR="/var/log/localai/reports"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
REPORT_FILE="$REPORTS_DIR/system-report-$TIMESTAMP.html"

mkdir -p "$REPORTS_DIR"

# Generate HTML report
cat > "$REPORT_FILE" << HTML_HEADER
<!DOCTYPE html>
<html>
<head>
    <title>LocalAI System Report - $TIMESTAMP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .section { margin-bottom: 30px; }
        .metric { background: #f5f5f5; padding: 10px; margin: 5px 0; }
        .alert { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        .healthy { color: green; font-weight: bold; }
    </style>
</head>
<body>
    <h1>LocalAI System Report</h1>
    <p>Generated: $TIMESTAMP</p>
HTML_HEADER

# System Overview
echo "<div class='section'><h2>System Overview</h2>" >> "$REPORT_FILE"
echo "<div class='metric'>Uptime: $(uptime)</div>" >> "$REPORT_FILE"
echo "<div class='metric'>Load Average: $(cat /proc/loadavg)</div>" >> "$REPORT_FILE"
echo "<div class='metric'>Disk Usage: $(df -h / | tail -1)</div>" >> "$REPORT_FILE"
echo "</div>" >> "$REPORT_FILE"

# Service Health
echo "<div class='section'><h2>Service Health</h2>" >> "$REPORT_FILE"
SERVICES=("n8n:5678" "openwebui:3000" "supabase:54321" "qdrant:6333" "neo4j:7474")
for service in "${SERVICES[@]}"; do
    NAME=$(echo "$service" | cut -d: -f1)
    PORT=$(echo "$service" | cut -d: -f2)
    if curl -f -s "http://localhost:$PORT" > /dev/null 2>&1; then
        STATUS="<span class='healthy'>HEALTHY</span>"
    else
        STATUS="<span class='alert'>DOWN</span>"
    fi
    echo "<div class='metric'>$NAME (port $PORT): $STATUS</div>" >> "$REPORT_FILE"
done
echo "</div>" >> "$REPORT_FILE"

# Recent Alerts
echo "<div class='section'><h2>Recent Alerts</h2>" >> "$REPORT_FILE"
ALERTS=$(find /var/log/localai/alerts -name "*.log" -newermt '24 hours ago' -exec tail -10 {} \; 2>/dev/null | head -20)
if [ -n "$ALERTS" ]; then
    echo "<pre>$ALERTS</pre>" >> "$REPORT_FILE"
else
    echo "<div class='metric'>No recent alerts</div>" >> "$REPORT_FILE"
fi
echo "</div>" >> "$REPORT_FILE"

# Close HTML
echo "</body></html>" >> "$REPORT_FILE"

echo "System report generated: $REPORT_FILE"
EOF

    chmod +x "$EXTERNAL_DIR/generate-reports.sh"

    # Set up daily report cron job
    (crontab -l 2>/dev/null; echo "0 8 * * * $EXTERNAL_DIR/generate-reports.sh") | crontab -

    echo "Automated report generation configured."
}

# Main execution
case "$1" in
    "install")
        mkdir -p "$EXTERNAL_DIR"
        install_external_tools
        ;;
    "uptimerobot")
        configure_uptimerobot_api
        ;;
    "alerting")
        configure_alerting
        configure_slack_integration
        ;;
    "grafana")
        configure_grafana_dashboards
        ;;
    "elk")
        configure_elk_pipelines
        ;;
    "reports")
        configure_automated_reports
        ;;
    "all")
        mkdir -p "$EXTERNAL_DIR"
        configure_uptimerobot_api
        configure_alerting
        configure_slack_integration
        configure_grafana_dashboards
        configure_elk_pipelines
        configure_automated_reports
        ;;
    *)
        echo "Usage: $0 {install|uptimerobot|alerting|grafana|elk|reports|all}"
        echo "  install     - Install external monitoring tools"
        echo "  uptimerobot - Configure UptimeRobot API integration"
        echo "  alerting    - Set up email and SMS alerting"
        echo "  grafana     - Configure Grafana dashboards"
        echo "  elk         - Configure ELK stack pipelines"
        echo "  reports     - Set up automated report generation"
        echo "  all         - Full setup of all external monitoring"
        exit 1
        ;;
esac

echo "External monitoring services setup completed for Ubuntu container."