#!/bin/bash

# Phase 4: SSL/TLS Certificate Management - Certificate Renewal Monitoring Script
# This script monitors Let's Encrypt certificate expiry and handles renewal

set -e

DOMAIN="supersmartinnovations.cloud"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"
LOG_FILE="/var/log/letsencrypt-renewal.log"
WARNING_DAYS=30
CRITICAL_DAYS=7

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Check if certificate exists
check_certificate_exists() {
    if [ ! -f "${CERT_PATH}/cert.pem" ]; then
        log "ERROR: Certificate not found at ${CERT_PATH}/cert.pem"
        echo -e "${RED}ERROR: Certificate not found at ${CERT_PATH}/cert.pem${NC}"
        return 1
    fi
    return 0
}

# Get certificate expiry information
get_cert_expiry() {
    if ! check_certificate_exists; then
        return 1
    fi

    # Get expiry date
    expiry_date=$(openssl x509 -enddate -noout -in "${CERT_PATH}/cert.pem" | cut -d= -f2)
    if [ -z "$expiry_date" ]; then
        log "ERROR: Could not read certificate expiry date"
        return 1
    fi

    # Convert to epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    if [ $? -ne 0 ]; then
        log "ERROR: Could not parse expiry date: $expiry_date"
        return 1
    fi

    current_epoch=$(date +%s)
    days_until_expiry=$(( ($expiry_epoch - $current_epoch) / 86400 ))

    echo "$days_until_expiry|$expiry_date"
    return 0
}

# Check certificate validity
check_certificate_validity() {
    log "Checking certificate validity for $DOMAIN"

    cert_info=$(get_cert_expiry)
    if [ $? -ne 0 ]; then
        return 1
    fi

    days_until_expiry=$(echo "$cert_info" | cut -d'|' -f1)
    expiry_date=$(echo "$cert_info" | cut -d'|' -f2)

    log "Certificate expires on: $expiry_date"
    log "Days until expiry: $days_until_expiry"

    # Determine status
    if [ "$days_until_expiry" -lt 0 ]; then
        echo -e "${RED}CRITICAL: Certificate has expired ($days_until_expiry days ago)!${NC}"
        log "CRITICAL: Certificate has expired ($days_until_expiry days ago)"
        return 2
    elif [ "$days_until_expiry" -le "$CRITICAL_DAYS" ]; then
        echo -e "${RED}CRITICAL: Certificate expires in $days_until_expiry days!${NC}"
        log "CRITICAL: Certificate expires in $days_until_expiry days"
        return 2
    elif [ "$days_until_expiry" -le "$WARNING_DAYS" ]; then
        echo -e "${YELLOW}WARNING: Certificate expires in $days_until_expiry days${NC}"
        log "WARNING: Certificate expires in $days_until_expiry days"
        return 1
    else
        echo -e "${GREEN}OK: Certificate is valid for $days_until_expiry more days${NC}"
        log "OK: Certificate is valid for $days_until_expiry more days"
        return 0
    fi
}

# Renew certificate
renew_certificate() {
    log "Starting certificate renewal process"

    # Check if Cloudflare credentials are available
    if [ -z "$CLOUDFLARE_EMAIL" ] || [ -z "$CLOUDFLARE_API_KEY" ]; then
        log "ERROR: Cloudflare credentials not provided for renewal"
        echo -e "${RED}ERROR: Cloudflare credentials required for renewal${NC}"
        return 1
    fi

    # Create temporary credentials file
    mkdir -p /tmp/certbot-renewal
    cat > /tmp/certbot-renewal/cloudflare.ini << EOF
dns_cloudflare_email = ${CLOUDFLARE_EMAIL}
dns_cloudflare_api_key = ${CLOUDFLARE_API_KEY}
EOF
    chmod 600 /tmp/certbot-renewal/cloudflare.ini

    # Attempt renewal
    echo -e "${BLUE}Attempting certificate renewal...${NC}"
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /tmp/certbot-renewal/cloudflare.ini \
        --email admin@supersmartinnovations.cloud \
        --agree-tos \
        --non-interactive \
        --domain ${DOMAIN} \
        --domain *.${DOMAIN} \
        --force-renewal

    if [ $? -eq 0 ]; then
        log "SUCCESS: Certificate renewed successfully"
        echo -e "${GREEN}SUCCESS: Certificate renewed successfully${NC}"

        # Clean up
        rm -rf /tmp/certbot-renewal

        # Reload Caddy to pick up new certificates
        echo -e "${BLUE}Reloading Caddy configuration...${NC}"
        if command -v caddy >/dev/null 2>&1; then
            caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
        fi

        return 0
    else
        log "ERROR: Certificate renewal failed"
        echo -e "${RED}ERROR: Certificate renewal failed${NC}"
        rm -rf /tmp/certbot-renewal
        return 1
    fi
}

# Main monitoring function
monitor_certificates() {
    echo -e "${BLUE}=================================${NC}"
    echo -e "${BLUE}Certificate Monitoring Check${NC}"
    echo -e "${BLUE}=================================${NC}"

    check_certificate_validity
    status=$?

    case $status in
        0)
            echo -e "${GREEN}Certificate status: OK${NC}"
            ;;
        1)
            echo -e "${YELLOW}Certificate status: WARNING${NC}"
            ;;
        2)
            echo -e "${RED}Certificate status: CRITICAL${NC}"
            # Attempt renewal if certificate is critical
            echo -e "${YELLOW}Attempting automatic renewal...${NC}"
            if renew_certificate; then
                echo -e "${GREEN}Renewal successful${NC}"
                # Re-check status after renewal
                check_certificate_validity >/dev/null
            else
                echo -e "${RED}Renewal failed${NC}"
            fi
            ;;
    esac

    echo -e "${BLUE}=================================${NC}"
    return $status
}

# Help function
show_help() {
    echo "Certificate Renewal Monitoring Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -m, --monitor    Run monitoring check (default)"
    echo "  -r, --renew      Force certificate renewal"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  CLOUDFLARE_EMAIL    Cloudflare account email"
    echo "  CLOUDFLARE_API_KEY  Cloudflare API key"
    echo ""
    echo "Examples:"
    echo "  $0                          # Run monitoring"
    echo "  $0 --renew                  # Force renewal"
    echo "  CLOUDFLARE_EMAIL=user@example.com CLOUDFLARE_API_KEY=key $0 --renew"
}

# Main script logic
case "${1:-}" in
    -m|--monitor|"")
        monitor_certificates
        ;;
    -r|--renew)
        if renew_certificate; then
            echo -e "${GREEN}Renewal completed successfully${NC}"
            exit 0
        else
            echo -e "${RED}Renewal failed${NC}"
            exit 1
        fi
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac

log "Script execution completed"