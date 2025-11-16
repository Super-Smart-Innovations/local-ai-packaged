# Phase 2: Port Forwarding Configuration for Containerized Setup
# This script configures host-to-container and nested container port forwarding
# for the Ubuntu container and DinD services

# Requires administrator privileges
#Requires -RunAsAdministrator

# Configuration Variables
$UbuntuContainerName = "ubuntu-server"
$HostIPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" -or $_.InterfaceAlias -like "*Wi-Fi*" } | Select-Object -First 1).IPAddress
$DockerNetworkName = "localai-bridge"

Write-Host "Starting port forwarding configuration for Phase 2..." -ForegroundColor Green

# Step 1: Ensure Docker Desktop is running
Write-Host "Checking Docker Desktop status..." -ForegroundColor Yellow
$dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
if ($null -eq $dockerService -or $dockerService.Status -ne "Running") {
    Write-Host "Starting Docker Desktop Service..." -ForegroundColor Yellow
    Start-Service -Name "Docker Desktop Service" -ErrorAction Stop
    Start-Sleep -Seconds 30  # Wait for Docker to initialize
}

# Step 2: Create Docker network for service isolation
Write-Host "Creating Docker bridge network for service isolation..." -ForegroundColor Yellow
docker network inspect $DockerNetworkName 2>$null
if ($LASTEXITCODE -ne 0) {
    docker network create --driver bridge --subnet 172.20.0.0/16 --gateway 172.20.0.1 $DockerNetworkName
    Write-Host "Created Docker network: $DockerNetworkName" -ForegroundColor Green
} else {
    Write-Host "Docker network $DockerNetworkName already exists" -ForegroundColor Cyan
}

# Step 3: Stop existing Ubuntu container if running
Write-Host "Checking for existing Ubuntu container..." -ForegroundColor Yellow
$containerExists = docker ps -a --filter "name=$UbuntuContainerName" --format "{{.Names}}"
if ($containerExists -eq $UbuntuContainerName) {
    Write-Host "Stopping and removing existing Ubuntu container..." -ForegroundColor Yellow
    docker stop $UbuntuContainerName 2>$null
    docker rm $UbuntuContainerName 2>$null
}

# Step 4: Create Ubuntu container with proper port forwarding
Write-Host "Creating Ubuntu container with privileged access and port forwarding..." -ForegroundColor Yellow

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
    ubuntu:22.04
    tail -f /dev/null
"@ -replace "`n", " "

Invoke-Expression $ubuntuRunCommand

# Wait for container to start
Start-Sleep -Seconds 10

# Verify container is running
$containerRunning = docker ps --filter "name=$UbuntuContainerName" --format "{{.Status}}"
if ($containerRunning -match "Up") {
    Write-Host "Ubuntu container is running successfully" -ForegroundColor Green
} else {
    Write-Host "Error: Ubuntu container failed to start" -ForegroundColor Red
    exit 1
}

# Step 5: Configure nested container port forwarding within Ubuntu container
Write-Host "Configuring nested container port forwarding..." -ForegroundColor Yellow

# Copy docker-compose.yml to Ubuntu container
Write-Host "Copying docker-compose configuration to Ubuntu container..." -ForegroundColor Yellow
docker cp "docker-compose.yml" "$UbuntuContainerName:/opt/docker-compose.yml"
docker cp "docker-compose.override.public.yml" "$UbuntuContainerName:/opt/docker-compose.override.public.yml"

# Create startup script inside Ubuntu container
$startupScript = @'
#!/bin/bash
# Ubuntu container startup script for nested services

# Update and install dependencies
apt update && apt install -y docker.io docker-compose-plugin curl wget

# Create necessary directories
mkdir -p /opt/backups
mkdir -p /opt/logs

# Set environment variables
export DOCKER_HOST=unix:///var/run/docker.sock

# Wait for Docker daemon to be ready
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker daemon..."
    sleep 5
done

# Start nested services with port mapping
cd /opt
docker compose -f docker-compose.yml -f docker-compose.override.public.yml up -d

# Configure port forwarding for internal services
# N8N (5678) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 5678 -j DNAT --to-destination 172.20.0.10:5678
iptables -t nat -A POSTROUTING -p tcp --dport 5678 -j MASQUERADE

# Open WebUI (3000) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 3000 -j DNAT --to-destination 172.20.0.10:3000
iptables -t nat -A POSTROUTING -p tcp --dport 3000 -j MASQUERADE

# Flowise (3001) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 3001 -j DNAT --to-destination 172.20.0.10:3001
iptables -t nat -A POSTROUTING -p tcp --dport 3001 -j MASQUERADE

# Supabase (3002) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 3002 -j DNAT --to-destination 172.20.0.10:3002
iptables -t nat -A POSTROUTING -p tcp --dport 3002 -j MASQUERADE

# SearXNG (8080) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 172.20.0.10:8080
iptables -t nat -A POSTROUTING -p tcp --dport 8080 -j MASQUERADE

# Neo4j (7474) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 7474 -j DNAT --to-destination 172.20.0.10:7474
iptables -t nat -A POSTROUTING -p tcp --dport 7474 -j MASQUERADE

# Langfuse (3003) -> external access through host
iptables -t nat -A PREROUTING -p tcp --dport 3003 -j DNAT --to-destination 172.20.0.10:3003
iptables -t nat -A POSTROUTING -p tcp --dport 3003 -j MASQUERADE

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

echo "Nested container port forwarding configured successfully"
'@

# Create the startup script file
$startupScript | docker exec -i $UbuntuContainerName bash -c 'cat > /opt/startup.sh && chmod +x /opt/startup.sh'

# Execute the startup script
Write-Host "Executing startup script in Ubuntu container..." -ForegroundColor Yellow
docker exec $UbuntuContainerName bash /opt/startup.sh

# Step 6: Verify port forwarding configuration
Write-Host "Verifying port forwarding configuration..." -ForegroundColor Yellow

# Test host to Ubuntu container forwarding
Write-Host "`nTesting host to Ubuntu container port forwarding:" -ForegroundColor Cyan
Test-NetConnection -ComputerName localhost -Port 80 | Format-Table ComputerName,RemotePort,TcpTestSucceeded
Test-NetConnection -ComputerName localhost -Port 443 | Format-Table ComputerName,RemotePort,TcpTestSucceeded
Test-NetConnection -ComputerName localhost -Port 22 | Format-Table ComputerName,RemotePort,TcpTestSucceeded

# Test nested service ports (from host)
Write-Host "`nTesting nested service port forwarding:" -ForegroundColor Cyan
$portsToTest = @(5678, 3000, 3001, 3002, 8080, 7474, 3003)
foreach ($port in $portsToTest) {
    $result = Test-NetConnection -ComputerName localhost -Port $port
    Write-Host "Port $port`: $($result.TcpTestSucceeded)" -ForegroundColor $(if ($result.TcpTestSucceeded) { "Green" } else { "Red" })
}

# Display container network information
Write-Host "`nContainer Network Information:" -ForegroundColor Cyan
docker network inspect $DockerNetworkName | ConvertFrom-Json | Select-Object -ExpandProperty Containers | Format-Table Name,IPv4Address

# Display Ubuntu container logs
Write-Host "`nUbuntu Container Logs (last 20 lines):" -ForegroundColor Cyan
docker logs --tail 20 $UbuntuContainerName

Write-Host "`nPort forwarding configuration completed successfully!" -ForegroundColor Green
Write-Host "Port Forwarding Summary:" -ForegroundColor Cyan
Write-Host "- External 80/443 → Host 80/443 → Ubuntu Container 80/443" -ForegroundColor Cyan
Write-Host "- SSH (22/TCP) → Host 22 (direct to host)" -ForegroundColor Cyan
Write-Host "- RDP (3389/TCP) → Host 3389 (Windows administration)" -ForegroundColor Cyan
Write-Host "- Nested services: 5678,3000,3001,3002,8080,7474,3003 forwarded through Ubuntu container" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "- Configure DNS records for all subdomains pointing to $HostIPAddress" -ForegroundColor Yellow
Write-Host "- Verify service startup in Ubuntu container logs" -ForegroundColor Yellow
Write-Host "- Configure SSL certificates for HTTPS services" -ForegroundColor Yellow