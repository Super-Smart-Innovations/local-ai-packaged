# Ubuntu Container Volume Backup Script
# This script creates automated backups of Ubuntu container data volumes

param(
    [string]$BackupPath = "C:\backups\ubuntu-volumes",
    [int]$RetentionDays = 30,
    [switch]$VerifyIntegrity
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

Write-Log "Starting Ubuntu volume backup to $backupDir"

# Get Docker volumes
$volumes = docker volume ls --format "{{.Name}}"

# Backup each volume
foreach ($volume in $volumes) {
    if ($volume -like "*ubuntu*" -or $volume -like "*container*") {
        Write-Log "Backing up volume: $volume"

        $volumeBackupDir = Join-Path $backupDir $volume
        New-Item -ItemType Directory -Path $volumeBackupDir | Out-Null

        # Create backup using docker run
        $backupCommand = "docker run --rm -v ${volume}:/source:ro -v ${volumeBackupDir}:/backup alpine tar czf /backup/${volume}.tar.gz -C /source ."
        Write-Log "Running: $backupCommand"

        try {
            $result = Invoke-Expression $backupCommand 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Successfully backed up $volume"
            } else {
                Write-Log "ERROR: Failed to backup $volume. Output: $result"
            }
        }
        catch {
            Write-Log "ERROR: Exception backing up $volume - $($_.Exception.Message)"
        }

        # Verify integrity if requested
        if ($VerifyIntegrity) {
            $archivePath = Join-Path $volumeBackupDir "${volume}.tar.gz"
            if (Test-Path $archivePath) {
                Write-Log "Verifying integrity of $archivePath"
                try {
                    $verifyResult = & tar -tzf $archivePath | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Integrity check passed for $volume"
                    } else {
                        Write-Log "ERROR: Integrity check failed for $volume"
                    }
                }
                catch {
                    Write-Log "ERROR: Could not verify integrity for $volume - $($_.Exception.Message)"
                }
            }
        }
    }
}

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

Write-Log "Backup completed successfully"