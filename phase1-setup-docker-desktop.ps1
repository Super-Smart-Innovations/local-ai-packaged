# PowerShell Script for Docker Desktop Installation and Configuration
# Phase 1: Windows Container Provisioning - Docker Desktop Setup

#Requires -RunAsAdministrator

Write-Host "=== Phase 1: Docker Desktop Installation and Configuration ===" -ForegroundColor Green
Write-Host "Host Specifications: Windows 11 Pro, 128GB RAM, 12-core CPU, 2TB SSD" -ForegroundColor Yellow
Write-Host "Container Specifications: Ubuntu 22.04, 64GB RAM, 12 CPU cores, 1TB storage" -ForegroundColor Yellow
Write-Host ""

# Check Windows version and specifications
Write-Host "Checking Windows specifications..." -ForegroundColor Cyan
$osInfo = Get-ComputerInfo
Write-Host "OS: $($osInfo.WindowsProductName) $($osInfo.WindowsVersion)" -ForegroundColor White
Write-Host "RAM: $([math]::Round($osInfo.TotalPhysicalMemory / 1GB, 0)) GB" -ForegroundColor White
Write-Host "CPU Cores: $($osInfo.NumberOfLogicalProcessors)" -ForegroundColor White

# Verify prerequisites
Write-Host "`nVerifying prerequisites..." -ForegroundColor Cyan
if ($osInfo.NumberOfLogicalProcessors -lt 12) {
    Write-Warning "Warning: System has fewer than 12 CPU cores. Performance may be impacted."
}
if ([math]::Round($osInfo.TotalPhysicalMemory / 1GB, 0) -lt 128) {
    Write-Warning "Warning: System has less than 128GB RAM. Performance may be impacted."
}

# Enable WSL2
Write-Host "`nEnabling WSL2..." -ForegroundColor Cyan
try {
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    Write-Host "WSL2 features enabled successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to enable WSL2 features: $_"
    exit 1
}

# Set WSL2 as default version
wsl --set-default-version 2
Write-Host "WSL2 set as default version." -ForegroundColor Green

# Install Ubuntu 22.04 if not present
Write-Host "`nChecking for Ubuntu 22.04 installation..." -ForegroundColor Cyan
$ubuntuInstalled = wsl -l -q | Where-Object { $_ -match "Ubuntu-22.04" }
if (-not $ubuntuInstalled) {
    Write-Host "Installing Ubuntu 22.04..." -ForegroundColor Yellow
    wsl --install -d Ubuntu-22.04
    Write-Host "Ubuntu 22.04 installed. Please complete the Ubuntu setup (username/password) when prompted." -ForegroundColor Green
} else {
    Write-Host "Ubuntu 22.04 is already installed." -ForegroundColor Green
}

# Download and install Docker Desktop
Write-Host "`nInstalling Docker Desktop..." -ForegroundColor Cyan
$dockerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
$installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

try {
    Invoke-WebRequest -Uri $dockerUrl -OutFile $installerPath
    Write-Host "Docker Desktop installer downloaded." -ForegroundColor Green

    # Install Docker Desktop silently
    Start-Process -FilePath $installerPath -ArgumentList "install --quiet" -Wait
    Write-Host "Docker Desktop installed successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to install Docker Desktop: $_"
    exit 1
}

# Start Docker Desktop service
Write-Host "`nStarting Docker Desktop..." -ForegroundColor Cyan
try {
    Start-Service -Name "Docker Desktop Service" -ErrorAction Stop
    Write-Host "Docker Desktop service started." -ForegroundColor Green
} catch {
    Write-Warning "Docker Desktop service may need manual start. Please start Docker Desktop from Start Menu."
}

# Configure Docker Desktop for production
Write-Host "`nConfiguring Docker Desktop for production..." -ForegroundColor Cyan

# Create Docker Desktop configuration directory if it doesn't exist
$dockerConfigPath = "$env:APPDATA\Docker Desktop"
if (-not (Test-Path $dockerConfigPath)) {
    New-Item -ItemType Directory -Path $dockerConfigPath -Force
}

# Docker Desktop settings.json for production optimization
$dockerSettings = @"
{
  "dockerDaemonSettings": {
    "storage-driver": "windowsfilter",
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "10m",
      "max-file": "3"
    },
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 10,
    "registry-mirrors": []
  },
  "experimental": true,
  "features": {
    "buildkit": true,
    "kubernetes": false
  },
  "proxy": {
    "http": "",
    "https": "",
    "exclude": []
  },
  "resourceLimits": {
    "cpu": 12,
    "memory": 64,
    "swap": 32
  }
}
"@

$settingsPath = "$dockerConfigPath\settings.json"
$dockerSettings | Out-File -FilePath $settingsPath -Encoding UTF8 -Force
Write-Host "Docker Desktop settings configured for production." -ForegroundColor Green

# Wait for Docker to be ready
Write-Host "`nWaiting for Docker to be ready..." -ForegroundColor Cyan
$maxRetries = 30
$retryCount = 0
do {
    try {
        $dockerVersion = docker version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker is ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Docker not ready yet
    }
    Start-Sleep -Seconds 10
    $retryCount++
    Write-Host "Waiting for Docker... ($retryCount/$maxRetries)" -ForegroundColor Yellow
} while ($retryCount -lt $maxRetries)

if ($retryCount -eq $maxRetries) {
    Write-Warning "Docker may not be fully ready. Please verify Docker Desktop is running and try the next script."
}

# Enable experimental features for privileged containers
Write-Host "`nEnabling experimental features for privileged containers..." -ForegroundColor Cyan
docker buildx install
Write-Host "BuildKit enabled for advanced container operations." -ForegroundColor Green

# Create Docker volumes for persistence
Write-Host "`nCreating Docker volumes for data persistence..." -ForegroundColor Cyan
docker volume create ubuntu-data
docker volume create ubuntu-certs
docker volume create ubuntu-logs
Write-Host "Docker volumes created: ubuntu-data, ubuntu-certs, ubuntu-logs" -ForegroundColor Green

# Verify Docker installation
Write-Host "`nVerifying Docker installation..." -ForegroundColor Cyan
docker system info | Select-String -Pattern "Operating System|Architecture|CPUs|Total Memory"
Write-Host "Docker verification complete." -ForegroundColor Green

Write-Host "`n=== Docker Desktop Setup Complete ===" -ForegroundColor Green
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Start Docker Desktop from Start Menu if not already running" -ForegroundColor White
Write-Host "2. Run the next script: phase1-ubuntu-container-setup.ps1" -ForegroundColor White
Write-Host "3. Complete Ubuntu initial setup (username/password) in WSL terminal" -ForegroundColor White

# Cleanup installer
if (Test-Path $installerPath) {
    Remove-Item $installerPath -Force
    Write-Host "Cleanup complete." -ForegroundColor Green
}