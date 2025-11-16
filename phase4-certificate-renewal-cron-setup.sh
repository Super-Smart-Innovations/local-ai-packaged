#!/bin/bash

# Phase 4: SSL/TLS Certificate Management - Cron Setup for Certificate Renewal
# This script sets up automated certificate renewal monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_SCRIPT="${SCRIPT_DIR}/phase4-certificate-renewal-monitoring.sh"
LOG_FILE="/var/log/letsencrypt-renewal.log"
CRON_JOB="0 2 * * * /bin/bash ${MONITORING_SCRIPT} --monitor >> ${LOG_FILE} 2>&1"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}=================================${NC}"
echo -e "${BLUE}Setting up Certificate Renewal Cron${NC}"
echo -e "${BLUE}=================================${NC}"

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root or with sudo${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Check if monitoring script exists
if [ ! -f "$MONITORING_SCRIPT" ]; then
    echo -e "${RED}ERROR: Monitoring script not found at $MONITORING_SCRIPT${NC}"
    exit 1
fi

# Make monitoring script executable
chmod +x "$MONITORING_SCRIPT"
echo -e "${GREEN}✓ Made monitoring script executable${NC}"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
echo -e "${GREEN}✓ Created log directory${NC}"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$MONITORING_SCRIPT"; then
    echo -e "${YELLOW}⚠️  Cron job already exists. Updating...${NC}"

    # Remove existing cron job
    crontab -l 2>/dev/null | grep -v "$MONITORING_SCRIPT" | crontab -
fi

# Add new cron job (runs daily at 2 AM)
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Certificate renewal cron job added successfully${NC}"
    echo -e "${BLUE}Cron schedule: Daily at 2:00 AM${NC}"
else
    echo -e "${RED}ERROR: Failed to add cron job${NC}"
    exit 1
fi

# Test the cron job
echo -e "${BLUE}Testing monitoring script...${NC}"
if bash "$MONITORING_SCRIPT" --monitor; then
    echo -e "${GREEN}✓ Monitoring script test passed${NC}"
else
    echo -e "${YELLOW}⚠️  Monitoring script test had warnings, but cron job was set up${NC}"
fi

# Display current cron jobs
echo -e "${BLUE}Current certificate-related cron jobs:${NC}"
crontab -l | grep -i letsencrypt || echo "  (No Let's Encrypt cron jobs found)"

echo ""
echo -e "${GREEN}=================================${NC}"
echo -e "${GREEN}Certificate renewal automation setup complete!${NC}"
echo -e "${GREEN}=================================${NC}"
echo ""
echo -e "${BLUE}Monitoring Details:${NC}"
echo "  - Script: $MONITORING_SCRIPT"
echo "  - Log file: $LOG_FILE"
echo "  - Schedule: Daily at 2:00 AM"
echo ""
echo -e "${BLUE}To view logs:${NC}"
echo "  tail -f $LOG_FILE"
echo ""
echo -e "${BLUE}To manually run monitoring:${NC}"
echo "  sudo $MONITORING_SCRIPT --monitor"
echo ""
echo -e "${BLUE}To force renewal:${NC}"
echo "  sudo CLOUDFLARE_EMAIL=your@email.com CLOUDFLARE_API_KEY=your_key $MONITORING_SCRIPT --renew"