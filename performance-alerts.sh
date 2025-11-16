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
if [ ! -f "$NOTIFICATION_CONFIG" ]; then
    echo "$DEFAULT_CONFIG" > "$NOTIFICATION_CONFIG"
    echo "Created default notification configuration: $NOTIFICATION_CONFIG"
    echo "Edit this file to enable notifications"
fi

# Track last notification times to prevent spam
declare -A LAST_NOTIFICATIONS

send_email_alert() {
    SUBJECT="$1"
    MESSAGE="$2"

    if command -v sendmail &> /dev/null; then
        echo "Subject: $SUBJECT" | sendmail -t "$EMAIL_RECIPIENT"
        echo "Email alert sent to $EMAIL_RECIPIENT"
    else
        echo "sendmail not available, skipping email notification"
    fi
}

send_slack_alert() {
    MESSAGE="$1"

    if [ ! -z "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
             --data "{\"text\":\"$MESSAGE\"}" \
             "$SLACK_WEBHOOK" 2>/dev/null
        echo "Slack alert sent"
    fi
}

send_webhook_alert() {
    ALERT_DATA="$1"

    if [ ! -z "$WEBHOOK_URL" ]; then
        curl -X POST -H "Content-Type: application/json" \
             -d "$ALERT_DATA" \
             "$WEBHOOK_URL" 2>/dev/null
        echo "Webhook alert sent"
    fi
}

process_alert() {
    ALERT_MESSAGE="$1"
    ALERT_TYPE="$2"
    CURRENT_TIME=$(date +%s)

    # Check cooldown
    LAST_TIME="${LAST_NOTIFICATIONS[$ALERT_TYPE]}"
    if [ ! -z "$LAST_TIME" ]; then
        TIME_DIFF=$((CURRENT_TIME - LAST_TIME))
        if [ "$TIME_DIFF" -lt "$NOTIFICATION_COOLDOWN" ]; then
            echo "Alert '' in cooldown, skipping notification"
            return
        fi
    fi

    LAST_NOTIFICATIONS[$ALERT_TYPE]=

    echo "Processing alert: $ALERT_MESSAGE"

    # Load notification configuration
    if [ -f "$NOTIFICATION_CONFIG" ]; then
        EMAIL_ENABLED=$(jq -r '.email.enabled // false' $NOTIFICATION_CONFIG)
        SLACK_ENABLED=$(jq -r '.slack.enabled // false' $NOTIFICATION_CONFIG)
        WEBHOOK_ENABLED=$(jq -r '.webhook.enabled // false' $NOTIFICATION_CONFIG)

        EMAIL_RECIPIENT=$(jq -r '.email.to_address // empty' $NOTIFICATION_CONFIG)
        SLACK_WEBHOOK=$(jq -r '.slack.webhook_url // empty' $NOTIFICATION_CONFIG)
        WEBHOOK_URL=$(jq -r '.webhook.url // empty' $NOTIFICATION_CONFIG)
    fi

    # Send notifications based on configuration
    if [ "$EMAIL_ENABLED" = "true" ] && [ ! -z "$EMAIL_RECIPIENT" ]; then
        send_email_alert "Performance Alert: $ALERT_TYPE" "$ALERT_MESSAGE"
    fi

    if [ "$SLACK_ENABLED" = "true" ] && [ ! -z "$SLACK_WEBHOOK" ]; then
        send_slack_alert "$ALERT_MESSAGE"
    fi

    if [ "$WEBHOOK_ENABLED" = "true" ] && [ ! -z "$WEBHOOK_URL" ]; then
        ALERT_DATA="{\"alert_type\":\"$ALERT_TYPE\",\"message\":\"$ALERT_MESSAGE\",\"timestamp\":\"$(date -Iseconds)\"}"
        send_webhook_alert "$ALERT_DATA"
    fi
}

# Monitor alert file for new alerts
echo "Starting alert processor..."
echo "Monitoring: $ALERT_FILE"
echo "Config: $NOTIFICATION_CONFIG"

if [ ! -f "$ALERT_FILE" ]; then
    echo "Alert file does not exist yet. It will be created when alerts occur."
    exit 1
fi

# Process existing alerts
tail -f "$ALERT_FILE" | while read line; do
    if [[ $line == *"[ALERT]"* ]]; then
        ALERT_MESSAGE=$(echo $line | sed 's/\[ALERT\]\s*\[[^]]*\]\s*//')
        ALERT_TYPE=$(echo $ALERT_MESSAGE | awk '{print $1}')  # First word as type
        process_alert "$ALERT_MESSAGE" "$ALERT_TYPE"
    fi
done
