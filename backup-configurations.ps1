# Configuration Backup Script
# This script backs up all configuration files and service-specific configs

param(
    [string]$BackupPath = "C:\backups\configurations",
    [int]$RetentionDays = 30,
    [switch]$VerifyIntegrity,
    [switch]$IncludeEnvFiles
)

# Configuration
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupPath $timestamp
$logFile = Join-Path $BackupPath "backup_log_$timestamp.txt"

# Function to log messages
function Write-Log {
    param([string]$Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Create backup directory
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

Write-Log "Starting configuration backup to $backupDir"

# Define configuration files and directories to backup
$configItems = @(
    # Docker Compose files
    "docker-compose.yml",
    "docker-compose.override.private.yml",
    "docker-compose.override.public.yml",
    "docker-compose.override.public.supabase.yml",

    # Core configuration files
    "Caddyfile",

    # SearXNG configuration
    "searxng/settings-base.yml",

    # Supabase configuration (if exists)
    "supabase/docker/.env.example",
    "supabase/docker/docker-compose.yml",

    # N8N workflows and configurations
    "n8n/backup",

    # Scripts and documentation
    "*.md",
    "*.ps1",
    "*.sh",
    "start_services.py"
)

# Environment files (optional - handle with care)
if ($IncludeEnvFiles) {
    $configItems += @(".env", ".env.local", ".env.production")
}

# Backup configuration files
foreach ($item in $configItems) {
    $sourcePath = Join-Path $PSScriptRoot $item

    if (Test-Path $sourcePath) {
        $files = Get-ChildItem $sourcePath -Recurse -File

        foreach ($file in $files) {
            $relativePath = $file.FullName.Replace($PSScriptRoot, "").TrimStart("\")
            $destPath = Join-Path $backupDir $relativePath

            $destDir = Split-Path $destPath -Parent
            if (!(Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            try {
                Copy-Item $file.FullName $destPath -Force
                Write-Log "Backed up: $relativePath"

                # Verify integrity if requested
                if ($VerifyIntegrity) {
                    $sourceHash = Get-FileHash $file.FullName -Algorithm SHA256
                    $destHash = Get-FileHash $destPath -Algorithm SHA256

                    if ($sourceHash.Hash -eq $destHash.Hash) {
                        Write-Log "Integrity verified: $relativePath"
                    } else {
                        Write-Log "ERROR: Integrity check failed for $relativePath"
                    }
                }
            }
            catch {
                Write-Log "ERROR: Failed to backup $relativePath - $($_.Exception.Message)"
            }
        }
    } else {
        Write-Log "Warning: Configuration item not found: $item"
    }
}

# Backup Docker image list for reproducibility
Write-Log "Backing up Docker image list"
$imageListFile = Join-Path $backupDir "docker_images.txt"
try {
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | Out-File -FilePath $imageListFile -Encoding UTF8
    Write-Log "Docker image list saved to docker_images.txt"
}
catch {
    Write-Log "Warning: Could not backup Docker image list - $($_.Exception.Message)"
}

# Backup Docker volume information
Write-Log "Backing up Docker volume information"
$volumeListFile = Join-Path $backupDir "docker_volumes.txt"
try {
    docker volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | Out-File -FilePath $volumeListFile -Encoding UTF8
    Write-Log "Docker volume list saved to docker_volumes.txt"
}
catch {
    Write-Log "Warning: Could not backup Docker volume information - $($_.Exception.Message)"
}

# Backup network information
Write-Log "Backing up Docker network information"
$networkListFile = Join-Path $backupDir "docker_networks.txt"
try {
    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | Out-File -FilePath $networkListFile -Encoding UTF8
    Write-Log "Docker network list saved to docker_networks.txt"
}
catch {
    Write-Log "Warning: Could not backup Docker network information - $($_.Exception.Message)"
}

# Create configuration change tracking
Write-Log "Creating configuration change tracking"
$changeLogFile = Join-Path $backupDir "configuration_changes.txt"

$changeContent = @"
Configuration Backup - $timestamp
=====================================

This backup includes:
- Docker Compose configuration files
- Caddy reverse proxy configuration
- SearXNG settings
- N8N workflow backups
- Documentation files
- Docker system information (images, volumes, networks)

Change Tracking:
- Compare file hashes between backups to identify changes
- Review git history for version control changes
- Check modification dates for recent updates

Restoration Notes:
- Restore configuration files before starting services
- Verify environment variables are set correctly
- Check file permissions after restoration
- Validate configurations before applying to production
"@

$changeContent | Out-File -FilePath $changeLogFile -Encoding UTF8

# Cleanup old backups
Write-Log "Cleaning up backups older than $RetentionDays days"
$oldBackups = Get-ChildItem $BackupPath -Directory | Where-Object {
    $_.Name -match '^\d{8}_\d{6}$' -and
    (Get-Date) - (Get-Date $_.Name.Substring(0,8)) -gt (New-TimeSpan -Days $RetentionDays)
}

foreach ($oldBackup in $oldBackups) {
    Write-Log "Removing old backup: $($oldBackup.FullName)"
    Remove-Item $oldBackup.FullName -Recurse -Force
}

# Generate backup summary
$summaryFile = Join-Path $BackupPath "backup_summary_$timestamp.txt"
$backupSize = (Get-ChildItem $backupDir -Recurse | Measure-Object -Property Length -Sum).Sum
$backupSizeMB = [math]::Round($backupSize / 1MB, 2)

$summaryContent = @"
Configuration Backup Summary
Generated: $(Get-Date)
Backup Location: $backupDir
Total Size: $backupSizeMB MB
Retention Policy: $RetentionDays days

Files Backed Up:
$(Get-ChildItem $backupDir -Recurse -File | Select-Object -ExpandProperty FullName | ForEach-Object { $_.Replace($backupDir, "") } | Out-String)
"@

$summaryContent | Out-File -FilePath $summaryFile -Encoding UTF8

Write-Log "Configuration backup completed successfully. Summary: $summaryFile"