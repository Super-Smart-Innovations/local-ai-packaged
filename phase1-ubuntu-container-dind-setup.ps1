# PowerShell Script for Ubuntu Container with Docker-in-Docker Setup
# Phase 1: Containerized Architecture Setup - Docker-in-Docker

#Requires -RunAsAdministrator

Write-Host "=== Phase 1: Ubuntu Container with Docker-in-Docker Setup ===" -ForegroundColor Green
Write-Host "Setting up Ubuntu 22.04 container with privileged access for Docker-in-Docker" -ForegroundColor Yellow
Write-Host ""

# Check if Docker is running
Write-Host "Checking Docker Desktop status..." -ForegroundColor Cyan
try {
    $dockerVersion = docker version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker Desktop is not running. Please start Docker Desktop and try again."
        exit 1
    }
    Write-Host "Docker is running." -ForegroundColor Green
} catch {
    Write-Error "Docker check failed: $_"
    exit 1
}

# Check for existing Ubuntu container
Write-Host "`nChecking for existing Ubuntu container..." -ForegroundColor Cyan
$existingContainer = docker ps -a --filter "name=ubuntu-server" --format "{{.Names}}"
if ($existingContainer) {
    Write-Host "Existing Ubuntu container found. Removing..." -ForegroundColor Yellow
    docker stop ubuntu-server 2>$null
    docker rm ubuntu-server 2>$null
    Write-Host "Existing container removed." -ForegroundColor Green
}

# Create custom Docker network for container isolation
Write-Host "`nCreating Docker network for container security..." -ForegroundColor Cyan
docker network create --driver bridge --subnet 172.20.0.0/16 --gateway 172.20.0.1 ubuntu-network 2>$null
Write-Host "Docker network 'ubuntu-network' created." -ForegroundColor Green

# Create Ubuntu container with Docker-in-Docker setup
Write-Host "`nCreating Ubuntu 22.04 container with Docker-in-Docker..." -ForegroundColor Cyan

$dockerRunCommand = @"
docker run -d --name ubuntu-server `
  --network ubuntu-network `
  --privileged `
  --restart unless-stopped `
  -p 80:80 -p 443:443 `
  -p 2222:22 `
  -v ubuntu-data:/data `
  -v ubuntu-certs:/etc/letsencrypt `
  -v ubuntu-logs:/var/log `
  -v //./pipe/docker_engine://./pipe/docker_engine `
  -e DOCKER_TLS_CERTDIR=/certs `
  --memory=96g --cpus=16 `
  --memory-swap=128g `
  --kernel-memory=16g `
  --pids-limit=8192 `
  --ulimit nofile=8192:8192 `
  --ulimit nproc=2048:2048 `
  --security-opt seccomp=unconfined `
  --cap-add=SYS_ADMIN `
  --cap-add=NET_ADMIN `
  --cap-add=SYS_PTRACE `
  ubuntu:22.04 `
  tail -f /dev/null
"@

Write-Host "Executing: $dockerRunCommand" -ForegroundColor Gray
Invoke-Expression $dockerRunCommand

if ($LASTEXITCODE -eq 0) {
    Write-Host "Ubuntu container created successfully." -ForegroundColor Green
} else {
    Write-Error "Failed to create Ubuntu container."
    exit 1
}

# Wait for container to be ready
Write-Host "`nWaiting for Ubuntu container to be ready..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

$maxRetries = 10
$retryCount = 0
do {
    $containerStatus = docker inspect ubuntu-server --format "{{.State.Running}}" 2>$null
    if ($containerStatus -eq "true") {
        Write-Host "Ubuntu container is running." -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 3
    $retryCount++
    Write-Host "Waiting for container... ($retryCount/$maxRetries)" -ForegroundColor Yellow
} while ($retryCount -lt $maxRetries)

if ($containerStatus -ne "true") {
    Write-Error "Ubuntu container failed to start properly."
    exit 1
}

# Configure Ubuntu container initial setup
Write-Host "`nConfiguring Ubuntu container..." -ForegroundColor Cyan

$ubuntuSetupScript = @"
#!/bin/bash
set -e

echo "=== Ubuntu Container Initial Setup ==="

# Update package lists
apt update && apt upgrade -y

# Install essential packages
apt install -y \
  curl \
  wget \
  git \
  vim \
  htop \
  iotop \
  ncdu \
  net-tools \
  openssh-server \
  docker.io \
  docker-compose-plugin \
  ufw \
  fail2ban \
  unattended-upgrades \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release

# Configure SSH
mkdir -p /var/run/sshd
echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
echo 'X11Forwarding no' >> /etc/ssh/sshd_config
service ssh start

# Install Docker Compose v2
curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Enable Docker service
service docker start
usermod -aG docker root

# Configure Docker daemon for DinD
cat > /etc/docker/daemon.json << EOF
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "registry-mirrors": [],
  "insecure-registries": [],
  "experimental": true,
  "features": {
    "buildkit": true
  }
}
EOF

# Restart Docker daemon
service docker restart

# Create necessary directories
mkdir -p /data /app /backups /scripts
chmod 755 /data /app /backups /scripts

# Configure firewall (allow SSH, HTTP, HTTPS)
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw default deny incoming
ufw default allow outgoing

# Configure fail2ban for SSH protection
cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

service fail2ban start

# Configure unattended upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
  "Ubuntu focal-security";
  "Ubuntu focal-updates";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

# Create log directories
mkdir -p /var/log/docker /var/log/containers
chmod 755 /var/log/docker /var/log/containers

# Set up basic monitoring
cat > /scripts/health-check.sh << 'EOF'
#!/bin/bash
echo "=== Container Health Check ==="
echo "Date: $(date)"
echo "Uptime: $(uptime)"
echo "Memory: $(free -h)"
echo "Disk: $(df -h /)"
echo "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'Not running')"
echo "Services: $(ps aux | grep -E '(docker|sshd)' | grep -v grep | wc -l) running"
EOF

chmod +x /scripts/health-check.sh

# Create backup script
cat > /scripts/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== Creating Backup ==="

# Backup Docker volumes
docker run --rm -v localai_n8n_storage:/source -v $BACKUP_DIR:/backup alpine tar czf /backup/n8n_$DATE.tar.gz -C /source .
docker run --rm -v localai_db_data:/source -v $BACKUP_DIR:/backup alpine tar czf /backup/db_$DATE.tar.gz -C /source .

# Clean old backups (keep last 30 days)
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup complete: $BACKUP_DIR"
EOF

chmod +x /scripts/backup.sh

# Create startup script for nested services
cat > /scripts/start-services.sh << 'EOF'
#!/bin/bash
echo "=== Starting Local AI Services ==="

# Set environment variables
export COMPOSE_PROJECT_NAME=localai
export COMPOSE_FILE=/app/docker-compose.yml

# Navigate to app directory
cd /app

# Start services
if [ -f "docker-compose.yml" ]; then
    docker compose up -d
    echo "Services started successfully"
else
    echo "docker-compose.yml not found in /app"
    exit 1
fi
EOF

chmod +x /scripts/start-services.sh

echo "=== Ubuntu Container Setup Complete ==="
"@

# Execute Ubuntu setup script
Write-Host "Executing Ubuntu setup script..." -ForegroundColor Yellow
$ubuntuSetupScript | docker exec -i ubuntu-server bash

if ($LASTEXITCODE -eq 0) {
    Write-Host "Ubuntu container configured successfully." -ForegroundColor Green
} else {
    Write-Error "Failed to configure Ubuntu container."
    exit 1
}

# Copy project files to container
Write-Host "`nCopying project files to Ubuntu container..." -ForegroundColor Cyan
$projectFiles = @(
    "docker-compose.yml",
    "docker-compose.override.public.yml",
    "start_services.py",
    "Caddyfile",
    ".env.example"
)

foreach ($file in $projectFiles) {
    if (Test-Path $file) {
        Write-Host "Copying $file..." -ForegroundColor Gray
        docker cp $file ubuntu-server:/app/
    } else {
        Write-Warning "File not found: $file"
    }
}

# Copy directories
$directories = @("db", "n8n", "supabase", "flowise", "searxng")
foreach ($dir in $directories) {
    if (Test-Path $dir) {
        Write-Host "Copying directory $dir..." -ForegroundColor Gray
        docker exec ubuntu-server mkdir -p /app/$dir
        docker cp $dir ubuntu-server:/app/$dir
    }
}

Write-Host "Project files copied to container." -ForegroundColor Green

# Test Docker-in-Docker functionality
Write-Host "`nTesting Docker-in-Docker functionality..." -ForegroundColor Cyan
$testResult = docker exec ubuntu-server docker run --rm hello-world 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Docker-in-Docker is working correctly." -ForegroundColor Green
} else {
    Write-Error "Docker-in-Docker test failed: $testResult"
}

# Configure Windows Firewall for container ports
Write-Host "`nConfiguring Windows Firewall for container access..." -ForegroundColor Cyan

# Allow HTTP and HTTPS
New-NetFirewallRule -DisplayName "HTTP (Ubuntu Container)" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName "HTTPS (Ubuntu Container)" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -Profile Any

# Allow SSH to container (port 2222)
New-NetFirewallRule -DisplayName "SSH (Ubuntu Container)" -Direction Inbound -Protocol TCP -LocalPort 2222 -Action Allow -Profile Any

Write-Host "Windows Firewall configured for container ports." -ForegroundColor Green

# Display container information
Write-Host "`n=== Ubuntu Container Setup Complete ===" -ForegroundColor Green
Write-Host "Container Information:" -ForegroundColor Yellow
docker ps --filter "name=ubuntu-server" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host "`nNetwork Information:" -ForegroundColor Yellow
docker inspect ubuntu-server --format "Container IP: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}"

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Access Ubuntu container: docker exec -it ubuntu-server bash" -ForegroundColor White
Write-Host "2. Test SSH access: ssh -p 2222 user@localhost" -ForegroundColor White
Write-Host "3. Run DNS configuration: phase1-dns-setup.ps1" -ForegroundColor White
Write-Host "4. Configure volume persistence and security" -ForegroundColor White

Write-Host "`n=== Phase 1 Container Setup Complete ===" -ForegroundColor Green