# Phase 2: Docker Network Isolation Configuration
# This script sets up Docker bridge networking with port forwarding
# and private networking for inter-container communication

# Requires administrator privileges
#Requires -RunAsAdministrator

# Configuration Variables
$DockerNetworkName = "localai-bridge"
$InternalNetworkName = "localai-internal"
$UbuntuContainerName = "ubuntu-server"
$NetworkSubnet = "172.20.0.0/16"
$NetworkGateway = "172.20.0.1"
$InternalSubnet = "172.21.0.0/16"
$InternalGateway = "172.21.0.1"

Write-Host "Starting Docker network isolation configuration for Phase 2..." -ForegroundColor Green

# Step 1: Ensure Docker Desktop is running
Write-Host "Checking Docker Desktop status..." -ForegroundColor Yellow
$dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
if ($null -eq $dockerService -or $dockerService.Status -ne "Running") {
    Write-Host "Starting Docker Desktop Service..." -ForegroundColor Yellow
    Start-Service -Name "Docker Desktop Service" -ErrorAction Stop
    Start-Sleep -Seconds 30
}

# Step 2: Remove existing networks if they exist (for clean setup)
Write-Host "Cleaning up existing networks if present..." -ForegroundColor Yellow
docker network rm $DockerNetworkName 2>$null
docker network rm $InternalNetworkName 2>$null

# Step 3: Create external bridge network (host-accessible)
Write-Host "Creating external bridge network for host access..." -ForegroundColor Yellow
docker network create `
    --driver bridge `
    --subnet $NetworkSubnet `
    --gateway $NetworkGateway `
    --opt "com.docker.network.bridge.name=localai0" `
    --opt "com.docker.network.bridge.enable_icc=true" `
    --opt "com.docker.network.bridge.enable_ip_masquerade=true" `
    --opt "com.docker.network.bridge.host_binding_ipv4=0.0.0.0" `
    --label "localai.external=true" `
    $DockerNetworkName

Write-Host "Created external bridge network: $DockerNetworkName" -ForegroundColor Green

# Step 4: Create internal private network (container-to-container only)
Write-Host "Creating internal private network for inter-container communication..." -ForegroundColor Yellow
docker network create `
    --driver bridge `
    --subnet $InternalSubnet `
    --gateway $InternalGateway `
    --opt "com.docker.network.bridge.name=localai1" `
    --opt "com.docker.network.bridge.enable_icc=true" `
    --opt "com.docker.network.bridge.enable_ip_masquerade=false" `
    --internal `
    --label "localai.internal=true" `
    $InternalNetworkName

Write-Host "Created internal private network: $InternalNetworkName" -ForegroundColor Green

# Step 5: Configure Windows Firewall rules for Docker networks
Write-Host "Configuring Windows Firewall rules for Docker networks..." -ForegroundColor Yellow

# Allow Docker bridge traffic
New-NetFirewallRule -DisplayName "Docker Bridge Network - External" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 80,443,22,5678,3000,3001,3002,8080,7474,3003 `
    -Action Allow `
    -Profile Any `
    -Description "Allow traffic to Docker bridge network ports"

# Block direct access to internal network ports
New-NetFirewallRule -DisplayName "Block Internal Network Direct Access" `
    -Direction Inbound `
    -Protocol TCP `
    -RemoteAddress "172.21.0.0/16" `
    -Action Block `
    -Profile Any `
    -Description "Block direct external access to internal Docker network"

# Step 6: Create Ubuntu container with network configuration
Write-Host "Configuring Ubuntu container with network isolation..." -ForegroundColor Yellow

# Stop existing container if running
$containerExists = docker ps -a --filter "name=$UbuntuContainerName" --format "{{.Names}}"
if ($containerExists -eq $UbuntuContainerName) {
    Write-Host "Stopping existing Ubuntu container for reconfiguration..." -ForegroundColor Yellow
    docker stop $UbuntuContainerName 2>$null
    docker rm $UbuntuContainerName 2>$null
}

# Create Ubuntu container connected to external network
$ubuntuRunCommand = @"
docker run -d --name $UbuntuContainerName
    --privileged
    --restart unless-stopped
    --network $DockerNetworkName
    --ip 172.20.0.10
    -p 80:80
    -p 443:443
    -p 22:22
    -v ubuntu-data:/data
    -v ubuntu-certs:/etc/letsencrypt
    -v //./pipe/docker_engine://./pipe/docker_engine
    -e DOCKER_TLS_CERTDIR=/certs
    --memory=64g --cpus=12
    --label "localai.ubuntu=true"
    ubuntu:22.04
    tail -f /dev/null
"@ -replace "`n", " "

Invoke-Expression $ubuntuRunCommand

# Wait for container to start
Start-Sleep -Seconds 10

# Step 7: Configure network isolation script within Ubuntu container
Write-Host "Configuring network isolation within Ubuntu container..." -ForegroundColor Yellow

$networkSetupScript = @'
#!/bin/bash
# Network isolation setup script for Ubuntu container

# Install network utilities
apt update && apt install -y iptables iptables-persistent net-tools curl

# Create internal network interface (connected via Docker network connect)
# Note: This will be connected when services start

# Configure iptables rules for network isolation
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from host
iptables -A INPUT -p tcp --dport 22 -s 172.20.0.1 -j ACCEPT

# Allow HTTP/HTTPS from anywhere (will be handled by Caddy)
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow internal network communication (when services are connected)
iptables -A INPUT -s 172.21.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 172.21.0.0/16 -j ACCEPT

# Allow DNS resolution
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT

# Allow NTP for time synchronization
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT

# Allow Docker daemon communication
iptables -A OUTPUT -p tcp --dport 2376 -j ACCEPT

# Allow service ports for nested containers
iptables -A INPUT -p tcp --dport 5678 -j ACCEPT  # N8N
iptables -A INPUT -p tcp --dport 3000 -j ACCEPT  # Open WebUI
iptables -A INPUT -p tcp --dport 3001 -j ACCEPT  # Flowise
iptables -A INPUT -p tcp --dport 3002 -j ACCEPT  # Supabase
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT  # SearXNG
iptables -A INPUT -p tcp --dport 7474 -j ACCEPT  # Neo4j
iptables -A INPUT -p tcp --dport 3003 -j ACCEPT  # Langfuse

# Rate limiting for protection against brute force
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

# Log dropped packets (rate limited)
iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-input-dropped: " --log-level 4
iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "iptables-forward-dropped: " --log-level 4

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Enable IP forwarding for container networking
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Create systemd service to maintain iptables rules on boot
cat > /etc/systemd/system/iptables-restore.service << EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable iptables-restore.service

echo "Network isolation configuration completed successfully"
'@

# Create and execute the network setup script
$networkSetupScript | docker exec -i $UbuntuContainerName bash -c 'cat > /opt/network-setup.sh && chmod +x /opt/network-setup.sh'
docker exec $UbuntuContainerName bash /opt/network-setup.sh

# Step 8: Create script for connecting services to internal network
Write-Host "Creating service network connection script..." -ForegroundColor Yellow

$connectServicesScript = @'
#!/bin/bash
# Script to connect nested services to internal network

# Function to safely connect container to internal network
connect_to_internal() {
    local container_name=$1
    local ip_address=$2

    echo "Connecting $container_name to internal network..."

    # Check if container exists and is running
    if docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        # Disconnect from any existing internal network connection
        docker network disconnect localai-internal $container_name 2>/dev/null

        # Connect to internal network with static IP
        docker network connect --ip $ip_address localai-internal $container_name
        echo "$container_name connected to internal network with IP $ip_address"
    else
        echo "Warning: Container $container_name not found or not running"
    fi
}

# Connect services to internal network (private communication only)
connect_to_internal "n8n" "172.21.0.10"
connect_to_internal "open-webui" "172.21.0.11"
connect_to_internal "flowise" "172.21.0.12"
connect_to_internal "supabase" "172.21.0.13"
connect_to_internal "searxng" "172.21.0.14"
connect_to_internal "neo4j" "172.21.0.15"
connect_to_internal "langfuse" "172.21.0.16"
connect_to_internal "qdrant" "172.21.0.17"
connect_to_internal "ollama" "172.21.0.18"

echo "Service network connections completed"
'@

# Create the service connection script
$connectServicesScript | docker exec -i $UbuntuContainerName bash -c 'cat > /opt/connect-services.sh && chmod +x /opt/connect-services.sh'

# Step 9: Verification and monitoring
Write-Host "Verifying network configuration..." -ForegroundColor Yellow

# Display network information
Write-Host "`nDocker Networks:" -ForegroundColor Cyan
docker network ls | Format-Table

# Display network details
Write-Host "`nExternal Network Details:" -ForegroundColor Cyan
docker network inspect $DockerNetworkName | ConvertFrom-Json | Select-Object -ExpandProperty IPAM -ExpandProperty Config

Write-Host "`nInternal Network Details:" -ForegroundColor Cyan
docker network inspect $InternalNetworkName | ConvertFrom-Json | Select-Object -ExpandProperty IPAM -ExpandProperty Config

# Display container network connections
Write-Host "`nContainer Network Connections:" -ForegroundColor Cyan
docker ps --format "table {{.Names}}\t{{.Networks}}"

# Test network connectivity
Write-Host "`nTesting network connectivity:" -ForegroundColor Cyan
docker exec $UbuntuContainerName ping -c 3 172.20.0.1  # Ping host
docker exec $UbuntuContainerName ping -c 3 172.21.0.1  # Ping internal gateway

# Display iptables rules
Write-Host "`nUbuntu Container iptables Rules:" -ForegroundColor Cyan
docker exec $UbuntuContainerName iptables -L -n | Select-String -Pattern "^(Chain|ACCEPT|DROP)"

Write-Host "`nDocker network isolation configuration completed successfully!" -ForegroundColor Green
Write-Host "Network Isolation Summary:" -ForegroundColor Cyan
Write-Host "- External Bridge Network: $DockerNetworkName ($NetworkSubnet)" -ForegroundColor Cyan
Write-Host "- Internal Private Network: $InternalNetworkName ($InternalSubnet)" -ForegroundColor Cyan
Write-Host "- Ubuntu Container IP: 172.20.0.10 (external network)" -ForegroundColor Cyan
Write-Host "- Services connected to both networks for secure communication" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "- Run '/opt/connect-services.sh' in Ubuntu container after services start" -ForegroundColor Yellow
Write-Host "- Verify inter-container communication through internal network" -ForegroundColor Yellow
Write-Host "- Monitor network traffic and adjust iptables rules as needed" -ForegroundColor Yellow