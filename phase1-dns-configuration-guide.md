# Phase 1: DNS Configuration Guide for supersmartinnovations.cloud

## Overview

This guide provides the DNS configuration steps for the primary domain `supersmartinnovations.cloud` and all subdomains as outlined in the production deployment plan. The setup supports the containerized Windows host architecture with nested services.

## DNS Records Configuration

### Primary Domain Records

Configure the following DNS records with your DNS provider (e.g., Namecheap, GoDaddy, Route 53):

```
; A Records for supersmartinnovations.cloud
supersmartinnovations.cloud.     IN A     [SERVER_IP]
www.supersmartinnovations.cloud. IN A     [SERVER_IP]

; A Records for subdomains
n8n.supersmartinnovations.cloud.      IN A     [SERVER_IP]
openwebui.supersmartinnovations.cloud. IN A     [SERVER_IP]
flowise.supersmartinnovations.cloud.   IN A     [SERVER_IP]
supabase.supersmartinnovations.cloud.  IN A     [SERVER_IP]
searxng.supersmartinnovations.cloud.   IN A     [SERVER_IP]
neo4j.supersmartinnovations.cloud.     IN A     [SERVER_IP]
langfuse.supersmartinnovations.cloud.  IN A     [SERVER_IP]
```

### DNS Configuration Details

- **Record Type**: A (Address) records for all domains
- **TTL (Time To Live)**: 3600 seconds (1 hour) - balances propagation speed with DNS server load
- **Target IP**: The public IP address of your Windows host server

### DNS Propagation Monitoring

Use the following commands to verify DNS propagation:

#### Windows Command Prompt
```cmd
nslookup supersmartinnovations.cloud
nslookup n8n.supersmartinnovations.cloud
nslookup openwebui.supersmartinnovations.cloud
ping supersmartinnovations.cloud
```

#### PowerShell Script for DNS Verification
```powershell
# PowerShell script to verify DNS configuration
$domains = @(
    "supersmartinnovations.cloud",
    "www.supersmartinnovations.cloud",
    "n8n.supersmartinnovations.cloud",
    "openwebui.supersmartinnovations.cloud",
    "flowise.supersmartinnovations.cloud",
    "supabase.supersmartinnovations.cloud",
    "searxng.supersmartinnovations.cloud",
    "neo4j.supersmartinnovations.cloud",
    "langfuse.supersmartinnovations.cloud"
)

Write-Host "=== DNS Propagation Check ===" -ForegroundColor Green
Write-Host "Date: $(Get-Date)" -ForegroundColor Yellow
Write-Host ""

foreach ($domain in $domains) {
    try {
        $result = Resolve-DnsName $domain -Type A -ErrorAction Stop
        Write-Host "$domain -> $($result.IPAddress)" -ForegroundColor Green
    } catch {
        Write-Host "$domain -> DNS lookup failed" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Note: DNS changes may take 24-48 hours to propagate globally." -ForegroundColor Yellow
```

## SSL Certificate Preparation (Let's Encrypt)

After DNS propagation is complete, prepare for SSL certificate generation:

### 1. DNS Challenge Preparation

For wildcard certificate generation, you'll need to add a TXT record for DNS validation:

```
_acme-challenge.supersmartinnovations.cloud. IN TXT "[CERTBOT_VALUE]"
```

This TXT record will be provided by Certbot during the certificate generation process in Phase 4.

### 2. Certificate Automation Setup

The certificates will be generated inside the Ubuntu container using Certbot with DNS validation. The certificates will be stored in the `ubuntu-certs` Docker volume for persistence.

## Network Architecture Context

### Port Forwarding Setup

The DNS configuration supports the following port forwarding architecture:

- **Host Server (Windows)**: Receives all traffic on ports 80/443
- **Ubuntu Container**: Forwards HTTP/HTTPS traffic through Caddy reverse proxy
- **Nested Services**: Individual services run on internal ports within the Ubuntu container

### Container Network Flow

```
Internet → DNS Resolution → [SERVER_IP]:80/443
    ↓
Windows Firewall (Allows 80/443)
    ↓
Ubuntu Container (Privileged + DinD)
    ↓
Caddy Reverse Proxy (SSL Termination)
    ↓
Nested Docker Services (n8n:5678, Open WebUI:3000, etc.)
```

## DNS Provider Specific Instructions

### Namecheap
1. Log into Namecheap account
2. Go to Domain List → Manage → Advanced DNS
3. Add A records for each subdomain pointing to [SERVER_IP]
4. Set TTL to 1 Hour (3600 seconds)

### GoDaddy
1. Log into GoDaddy account
2. Go to Domains → DNS Management
3. Add Type A records for each subdomain
4. Set TTL to 1 Hour

### AWS Route 53
1. Create Hosted Zone for supersmartinnovations.cloud
2. Create A records for root domain and subdomains
3. Set TTL to 3600 seconds
4. Update nameservers with domain registrar

### Cloudflare
1. Add domain to Cloudflare
2. Create A records for each subdomain
3. Set TTL to Auto (or 1 hour minimum)
4. Enable proxying if desired (Orange cloud icon)

## Troubleshooting DNS Issues

### Common DNS Problems

1. **Propagation Delay**: DNS changes can take 24-48 hours to propagate globally
2. **TTL Caching**: Old records may be cached for up to the TTL period
3. **Registrar Nameservers**: Ensure nameservers are correctly updated with registrar

### Verification Tools

- **Online DNS Checkers**: dnschecker.org, whatsmydns.net
- **Dig Command**: `dig supersmartinnovations.cloud A`
- **Global Propagation**: Check from multiple geographic locations

### Emergency DNS Rollback

If DNS issues occur, you can temporarily use the server's direct IP address to access services:

- N8N: `http://[SERVER_IP]:5678`
- Open WebUI: `http://[SERVER_IP]:3000`
- Other services: Check docker-compose.yml for port mappings

## Security Considerations

### DNS Security Best Practices

1. **DNSSEC**: Enable DNSSEC if supported by your DNS provider
2. **Rate Limiting**: Implement rate limiting on DNS queries if available
3. **Monitoring**: Monitor for DNS amplification attacks
4. **Backup DNS**: Consider secondary DNS provider for redundancy

### SSL/TLS Configuration

The DNS setup prepares for automatic SSL certificate management through Let's Encrypt, ensuring all subdomains have valid certificates for secure HTTPS access.

## Next Steps

After DNS configuration is complete:

1. **Verify Propagation**: Use the provided PowerShell script to verify all domains resolve correctly
2. **SSL Certificate Generation**: Proceed to Phase 4 for Let's Encrypt certificate setup
3. **Service Deployment**: Deploy the local-ai-packaged services within the Ubuntu container
4. **Access Testing**: Test HTTPS access to all subdomains through the Caddy reverse proxy

## Configuration Checklist

- [ ] Primary domain (supersmartinnovations.cloud) points to server IP
- [ ] All subdomains (n8n, openwebui, flowise, etc.) point to server IP
- [ ] TTL set to 3600 seconds (1 hour)
- [ ] DNS propagation verified using multiple tools
- [ ] SSL certificate preparation completed (TXT record ready for ACME challenge)
- [ ] Firewall allows inbound traffic on ports 80/443
- [ ] Ubuntu container accessible on internal network
- [ ] Caddy configuration ready for SSL termination

## Contact Information

For DNS configuration support:
- **Domain Registrar Support**: Contact your DNS provider's support team
- **Technical Support**: admin@supersmartinnovations.cloud
- **Documentation**: This guide and production deployment plan

---

**Document Version**: 1.0
**Last Updated**: November 2025
**Applies To**: Phase 1 - Infrastructure and DNS Setup