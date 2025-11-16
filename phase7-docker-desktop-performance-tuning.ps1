# Phase 7: Docker Desktop Performance Optimization
# This script optimizes Docker Desktop settings for production workloads

$dockerSettingsPath = "$env:USERPROFILE\AppData\Roaming\Docker\settings.json"
$backupPath = "$dockerSettingsPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host "Optimizing Docker Desktop performance settings..." -ForegroundColor Green

# Check if Docker Desktop is running
$dockerProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
if ($dockerProcess) {
    Write-Host "Docker Desktop is running. Please close Docker Desktop before running this script." -ForegroundColor Red
    exit 1
}

# Backup current settings
if (Test-Path $dockerSettingsPath) {
    Copy-Item $dockerSettingsPath $backupPath
    Write-Host "Backed up current settings to: $backupPath" -ForegroundColor Yellow
} else {
    Write-Host "No existing settings.json found. Creating optimized configuration." -ForegroundColor Yellow
}

# Optimized Docker Desktop settings for production workloads
$optimizedSettings = @{
    "builder" = @{
        "gc" = @{
            "enabled" = $true
            "defaultKeepStorage" = "50GB"
            "maxKeepStorage" = "100GB"
        }
    }
    "experimental" = $true
    "features" = @{
        "buildkit" = $true
    }
    "dockerDaemonOptions" = @{
        "log-driver" = "json-file"
        "log-opts" = @{
            "max-size" = "100m"
            "max-file" = "5"
        }
        "storage-driver" = "overlay2"
        "max-concurrent-downloads" = 10
        "max-concurrent-uploads" = 10
        "registry-mirrors" = @()
        "insecure-registries" = @()
        "experimental" = $true
        "metrics-addr" = "127.0.0.1:9323"
        "debug" = $false
    }
    "kubernetes" = @{
        "enabled" = $false
    }
    "analyticsEnabled" = $false
    "autoStart" = $true
    "displayedOnboarding" = $true
    "filesharingDirectories" = @(
        "C:\dev-env.local"
    )
    "proxyHttpMode" = "system"
    "proxyHttpsMode" = "system"
    "useVirtualizationFrameworkRosetta" = $false
    "useVirtualizationFrameworkVirtioFS" = $false
    "vmType" = "WSL"
    "wslEngineEnabled" = $true
    "windowsContainers" = $false
}

# Convert to JSON and save
$optimizedSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $dockerSettingsPath -Encoding UTF8

Write-Host "Docker Desktop settings optimized successfully." -ForegroundColor Green
Write-Host "Please restart Docker Desktop to apply the changes." -ForegroundColor Yellow
Write-Host ""
Write-Host "Key optimizations applied:" -ForegroundColor Cyan
Write-Host "- BuildKit enabled for faster builds"
Write-Host "- Experimental features enabled"
Write-Host "- Optimized garbage collection (50GB keep, 100GB max)"
Write-Host "- JSON log driver with rotation (100MB max size, 5 files)"
Write-Host "- Concurrent downloads/uploads increased to 10"
Write-Host "- Metrics enabled on localhost:9323"
Write-Host "- Analytics disabled for performance"