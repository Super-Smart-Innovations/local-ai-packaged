#!/bin/bash

# Phase 4: SSL/TLS Certificate Management - Certbot Certificate Generation Script
# This script runs inside an Ubuntu container to generate Let's Encrypt certificates

set -e

DOMAIN="supersmartinnovations.cloud"
WILDCARD_DOMAIN="*.supersmartinnovations.cloud"
EMAIL="admin@supersmartinnovations.cloud"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"

echo "================================="
echo "Let's Encrypt Certificate Generation"
echo "Domain: ${DOMAIN}"
echo "Wildcard: ${WILDCARD_DOMAIN}"
echo "Email: ${EMAIL}"
echo "================================="

# Update package list
echo "Updating package list..."
apt-get update -y

# Install certbot and dns challenge plugin
echo "Installing certbot and DNS challenge plugin..."
apt-get install -y certbot python3-certbot-dns-cloudflare

# Create certificate directory if it doesn't exist
mkdir -p /etc/letsencrypt

# Check if certificate already exists
if [ -d "${CERT_PATH}" ]; then
    echo "Certificate already exists at ${CERT_PATH}"
    echo "Checking certificate validity..."

    # Check certificate expiry
    cert_expiry=$(openssl x509 -enddate -noout -in "${CERT_PATH}/cert.pem" | cut -d= -f2)
    cert_expiry_epoch=$(date -d "$cert_expiry" +%s)
    current_epoch=$(date +%s)
    days_until_expiry=$(( ($cert_expiry_epoch - $current_epoch) / 86400 ))

    echo "Certificate expires on: $cert_expiry"
    echo "Days until expiry: $days_until_expiry"

    if [ "$days_until_expiry" -gt 30 ]; then
        echo "Certificate is still valid (>30 days). Skipping generation."
        exit 0
    else
        echo "Certificate expires soon. Proceeding with renewal."
    fi
fi

# Check if Cloudflare credentials are provided
if [ -z "$CLOUDFLARE_EMAIL" ] || [ -z "$CLOUDFLARE_API_KEY" ]; then
    echo "ERROR: Cloudflare credentials not provided."
    echo "Please set CLOUDFLARE_EMAIL and CLOUDFLARE_API_KEY environment variables."
    echo ""
    echo "For DNS-01 challenge, you need to provide Cloudflare API credentials."
    echo "Get your API key from: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "Usage: docker run -e CLOUDFLARE_EMAIL=your@email.com -e CLOUDFLARE_API_KEY=your_api_key ..."
    exit 1
fi

# Create Cloudflare credentials file
echo "Creating Cloudflare credentials file..."
cat > /root/.secrets/certbot/cloudflare.ini << EOF
dns_cloudflare_email = ${CLOUDFLARE_EMAIL}
dns_cloudflare_api_key = ${CLOUDFLARE_API_KEY}
EOF

chmod 600 /root/.secrets/certbot/cloudflare.ini

echo "================================="
echo "Starting certificate generation..."
echo "This will perform a DNS-01 challenge with Cloudflare"
echo "================================="

# Generate wildcard certificate using DNS challenge
certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
    --email ${EMAIL} \
    --agree-tos \
    --non-interactive \
    --domain ${DOMAIN} \
    --domain ${WILDCARD_DOMAIN}

# Verify certificate generation
echo "Verifying certificate generation..."
if [ -f "${CERT_PATH}/fullchain.pem" ] && [ -f "${CERT_PATH}/privkey.pem" ]; then
    echo "SUCCESS: Certificate generated successfully!"
    echo "Certificate files:"
    ls -la ${CERT_PATH}/

    echo ""
    echo "Certificate details:"
    openssl x509 -in "${CERT_PATH}/cert.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After :|DNS:)"

    echo ""
    echo "================================="
    echo "Certificate generation completed!"
    echo "Files are available at: ${CERT_PATH}"
    echo "================================="
else
    echo "ERROR: Certificate generation failed!"
    exit 1
fi

# Clean up sensitive files (credentials file will be removed by container cleanup)
echo "Cleaning up temporary files..."
rm -f /root/.secrets/certbot/cloudflare.ini

echo "Script completed successfully."