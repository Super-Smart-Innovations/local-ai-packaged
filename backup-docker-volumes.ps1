# Docker Volume Backup Script
# This script creates backups of Docker volumes using volume mount points

param(
    [string]$BackupPath = "C:\backups\docker-volumes",
    [int]$RetentionDays = 30,
    [switch]$VerifyIntegrity,
    [string[]]$IncludeVolumes = @(),
    [string[]]$ExcludeVolumes = @()
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

Write-Log "Starting Docker volume backup to $backupDir"

# Get Docker volumes
$allVolumes = docker volume ls --format "{{.Name}}"

# Filter volumes
$volumesToBackup = @()

foreach ($volume in $allVolumes) {
    $shouldInclude = $true

    # Check exclusions
    foreach ($exclude in $ExcludeVolumes) {
        if ($volume -like $exclude) {
            $shouldInclude = $false
            break
        }
    }

    # If inclusions specified, only include matching volumes
    if ($IncludeVolumes.Count -gt 0) {
        $shouldInclude = $false
        foreach ($include in $IncludeVolumes) {
            if ($volume -like $include) {
                $shouldInclude = $true
                break
            }
        }
    }

    if ($shouldInclude) {
        $volumesToBackup += $volume
    }
}

Write-Log "Backing up volumes: $($volumesToBackup -join ', ')"

# Backup each volume
foreach ($volume in $volumesToBackup) {
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

            # Verify integrity if requested
            if ($VerifyIntegrity) {
                $archivePath = Join-Path $volumeBackupDir "${volume}.tar.gz"
                if (Test-Path $archivePath) {
                    Write-Log "Verifying integrity of $archivePath"

                    # Use 7zip if available, otherwise tar
                    try {
                        if (Get-Command 7z -ErrorAction SilentlyContinue) {
                            $verifyResult = & 7z t "$archivePath" 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-Log "Integrity check passed for $volume"
                            } else {
                                Write-Log "ERROR: Integrity check failed for $volume"
                            }
                        } else {
                            # Fallback to tar (requires Git Bash or similar)
                            $env:Path += ";C:\Program Files\Git\bin"
                            $verifyResult = & tar -tzf "$archivePath" 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Write-Log "Integrity check passed for $volume"
                            } else {
                                Write-Log "ERROR: Integrity check failed for $volume"
                            }
                        }
                    }
                    catch {
                        Write-Log "ERROR: Could not verify integrity for $volume - $($_.Exception.Message)"
                    }
                }
            }

            # Calculate and log backup size
            $backupSize = (Get-Item (Join-Path $volumeBackupDir "${volume}.tar.gz")).Length
            $backupSizeMB = [math]::Round($backupSize / 1MB, 2)
            Write-Log "Backup size for $volume`: $backupSizeMB MB"

        } else {
            Write-Log "ERROR: Failed to backup $volume. Output: $result"
        }
    }
    catch {
        Write-Log "ERROR: Exception backing up $volume - $($_.Exception.Message)"
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

# Generate backup report
$reportFile = Join-Path $BackupPath "backup_report_$timestamp.txt"
$reportContent = @"
Docker Volume Backup Report
Generated: $(Get-Date)
Backup Location: $backupDir
Retention Policy: $RetentionDays days

Volumes Backed Up:
$($volumesToBackup | ForEach-Object { "- $_" } | Out-String)

Backup Sizes:
$(Get-ChildItem $backupDir -Recurse -File | Where-Object { $_.Extension -eq '.gz' } | ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    "- $($_.Directory.Name)/$($_.Name): $sizeMB MB"
} | Out-String)
"@

$reportContent | Out-File -FilePath $reportFile -Encoding UTF8

Write-Log "Backup report generated: $reportFile"
Write-Log "Docker volume backup completed successfully"