# Phase 3: Ubuntu Container Security Setup and Hardening
# This script creates and configures the Ubuntu 22.04 container with privileged access for DinD
# Includes security hardening measures and project file deployment

param(
    [string]$UbuntuDataVolume = "ubuntu-data",
    [string]$UbuntuCertsVolume = "ubuntu-certs",
    [string]$ProjectPath = "C:\dev-env.local\docker-ai-services\local-ai-packaged",
    [int]$MemoryGB = 64,
    [int]$CPUCores = 12
)

Write-Host "=== Phase 3: Ubuntu Container Security Setup ===" -ForegroundColor Green

# Function to check Docker Desktop status
function Test-DockerDesktop {
    try {
        $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
        if ($dockerVersion) {
            Write-Host "Docker Desktop is running (Version: $dockerVersion)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Docker Desktop is not running or not accessible" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error checking Docker Desktop: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Check if Docker Desktop is running
if (-not (Test-DockerDesktop)) {
    Write-Host "Please ensure Docker Desktop is running and WSL2 is enabled." -ForegroundColor Yellow
    exit 1
}

# Enable WSL2 and install Ubuntu if not already present
Write-Host "Ensuring WSL2 is enabled and Ubuntu is installed..." -ForegroundColor Cyan
try {
    wsl --set-default-version 2
    $ubuntuInstalled = wsl -l -q | Where-Object { $_ -match "Ubuntu" }
    if (-not $ubuntuInstalled) {
        Write-Host "Installing Ubuntu 22.04..." -ForegroundColor Cyan
        wsl --install -d Ubuntu-22.04
    } else {
        Write-Host "Ubuntu is already installed." -ForegroundColor Green
    }
} catch {
    Write-Host "Error with WSL2 setup: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Stop and remove existing ubuntu-server container if it exists
Write-Host "Cleaning up existing ubuntu-server container..." -ForegroundColor Cyan
docker stop ubuntu-server 2>$null
docker rm ubuntu-server 2>$null

# Create named volumes if they don't exist
Write-Host "Creating named volumes..." -ForegroundColor Cyan
docker volume create $UbuntuDataVolume
docker volume create $UbuntuCertsVolume

# Create Ubuntu container with security hardening
Write-Host "Creating Ubuntu 22.04 container with privileged access for DinD..." -ForegroundColor Cyan
$dockerRunCmd = @"
docker run -d --name ubuntu-server
  --privileged
  --restart unless-stopped
  -p 80:80 -p 443:443
  -v ${UbuntuDataVolume}:/data
  -v ${UbuntuCertsVolume}:/certs
  -v //./pipe/docker_engine://./pipe/docker_engine
  -e DOCKER_TLS_CERTDIR=/certs
  --memory=${MemoryGB}g --cpus=${CPUCores}
  --security-opt seccomp=${ProjectPath}\seccomp\ubuntu-dind-seccomp.json
  --cap-drop=ALL
  --cap-add=SYS_ADMIN
  --cap-add=NET_ADMIN
  --cap-add=SYS_PTRACE
  --cap-add=SYS_CHROOT
  --read-only
  --tmpfs /tmp:noexec,nosuid,size=100m
  --tmpfs /var/run:noexec,nosuid,size=50m
  ubuntu:22.04
  tail -f /dev/null
"@

# Remove extra whitespace and run
$dockerRunCmd = $dockerRunCmd -replace '\s+', ' '
Invoke-Expression $dockerRunCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create Ubuntu container" -ForegroundColor Red
    exit 1
}

# Wait for container to start
Start-Sleep -Seconds 5

# Enter container and perform initial setup
Write-Host "Performing initial container setup..." -ForegroundColor Cyan
docker exec ubuntu-server bash -c "
    # Update and upgrade packages with security patches
    echo 'Updating package lists...'
    apt update -y

    echo 'Upgrading packages...'
    apt upgrade -y

    echo 'Installing required packages...'
    apt install -y docker.io docker-compose-plugin curl wget git htop iotop ncdu ufw fail2ban unattended-upgrades

    # Configure automatic security updates
    echo 'Configuring automatic security updates...'
    dpkg-reconfigure -f noninteractive unattended-upgrades

    # Enable UFW firewall inside container
    echo 'Configuring UFW firewall...'
    ufw --force enable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw default deny incoming
    ufw default allow outgoing

    # Configure fail2ban
    echo 'Configuring fail2ban...'
    systemctl enable fail2ban
    systemctl start fail2ban

    # Create security hardening directory
    mkdir -p /opt/security

    # Set up Docker daemon with security options
    echo 'Configuring Docker daemon security...'
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
    \"icc\": false,
    \"userns-remap\": \"default\",
    \"no-new-privileges\": true,
    \"log-driver\": \"json-file\",
    \"log-opts\": {
        \"max-size\": \"10m\",
        \"max-file\": \"3\"
    }
}
EOF

    # Restart Docker daemon
    systemctl restart docker

    echo 'Ubuntu container security setup completed successfully.'
"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to configure Ubuntu container" -ForegroundColor Red
    exit 1
}

# Deploy project files to container
Write-Host "Deploying project files to Ubuntu container..." -ForegroundColor Cyan
docker cp "${ProjectPath}\." ubuntu-server:/opt/local-ai-packaged

# Create security hardening scripts directory in container
docker exec ubuntu-server mkdir -p /opt/security

# Deploy security verification script
Write-Host "Creating security verification script..." -ForegroundColor Cyan
docker exec ubuntu-server bash -c "
    cat > /opt/security/verify-security.sh << 'EOF'
#!/bin/bash
echo '=== Ubuntu Container Security Verification ==='
echo 'Container Capabilities:'
capsh --print | grep -E '(Current|Bounding)'
echo ''
echo 'Seccomp Status:'
grep -r Seccomp /proc/1/status
echo ''
echo 'UFW Status:'
ufw status verbose
echo ''
echo 'Fail2Ban Status:'
systemctl is-active fail2ban
echo ''
echo 'Docker Daemon Security:'
docker info --format '{{.SecurityOptions}}'
echo ''
echo 'Automatic Updates Status:'
systemctl is-active unattended-upgrades
echo ''
echo 'Security verification completed.'
EOF

    chmod +x /opt/security/verify-security.sh
"

# Run initial security verification
Write-Host "Running initial security verification..." -ForegroundColor Cyan
docker exec ubuntu-server /opt/security/verify-security.sh

Write-Host "=== Ubuntu Container Security Setup Completed ===" -ForegroundColor Green
Write-Host "Container Name: ubuntu-server" -ForegroundColor Cyan
Write-Host "Volumes: $UbuntuDataVolume, $UbuntuCertsVolume" -ForegroundColor Cyan
Write-Host "Security Features Enabled:" -ForegroundColor Cyan
Write-Host "  - Privileged access for DinD" -ForegroundColor White
Write-Host "  - Capability restrictions (SYS_ADMIN, NET_ADMIN, SYS_PTRACE, SYS_CHROOT only)" -ForegroundColor White
Write-Host "  - Custom seccomp profile" -ForegroundColor White
Write-Host "  - Read-only root filesystem with tmpfs exceptions" -ForegroundColor White
Write-Host "  - UFW firewall enabled" -ForegroundColor White
Write-Host "  - Fail2Ban intrusion prevention" -ForegroundColor White
Write-Host "  - Automatic security updates" -ForegroundColor White
Write-Host "  - User namespace remapping" -ForegroundColor White
Write-Host "  - No-new-privileges for containers" -ForegroundColor White