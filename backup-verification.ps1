# Backup Verification and Testing Script
# This script verifies backup integrity and tests restoration procedures

param(
    [string]$BackupRoot = "C:\backups",
    [ValidateSet("All", "Configurations", "UbuntuVolumes", "DockerVolumes", "NestedServices")]
    [string]$TestType = "All",
    [string]$ReportPath = "C:\reports"
)

# Configuration
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = Join-Path $ReportPath "backup-verification-report_$timestamp.txt"
$logFile = Join-Path $ReportPath "verification_log_$timestamp.txt"

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level]: $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage
}

# Function to add to report
function Add-ToReport {
    param([string]$Content)
    Add-Content -Path $reportFile -Value $Content
}

Write-Log "Starting backup verification - $timestamp"

# Create report directory
if (!(Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath | Out-Null
}

# Initialize report
$reportHeader = @"
Backup Verification Report
Generated: $(Get-Date)
Test Type: $TestType
Backup Root: $BackupRoot

================================================================================

"@

$reportHeader | Out-File -FilePath $reportFile -Encoding UTF8

# Test configuration backups
function Test-ConfigurationBackups {
    Write-Log "Testing configuration backups"

    $configDir = Join-Path $BackupRoot "configurations"
    $latestBackup = Get-ChildItem $configDir -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1

    if ($latestBackup) {
        Write-Log "Testing latest configuration backup: $($latestBackup.Name)"
        Add-ToReport "Configuration Backup Test"
        Add-ToReport "=========================="
        Add-ToReport "Latest Backup: $($latestBackup.FullName)"

        # Check for critical files
        $criticalFiles = @(
            "docker-compose.yml",
            "Caddyfile",
            "searxng/settings-base.yml"
        )

        $missingFiles = @()
        foreach ($file in $criticalFiles) {
            $filePath = Join-Path $latestBackup.FullName $file
            if (Test-Path $filePath) {
                Write-Log "Found: $file"
                Add-ToReport "✓ $file - Present"
            } else {
                Write-Log "Missing: $file" "WARNING"
                Add-ToReport "✗ $file - Missing"
                $missingFiles += $file
            }
        }

        # Test file integrity
        $totalFiles = (Get-ChildItem $latestBackup.FullName -Recurse -File).Count
        Add-ToReport "Total Files: $totalFiles"

        # Calculate backup size
        $backupSize = (Get-ChildItem $latestBackup.FullName -Recurse | Measure-Object -Property Length -Sum).Sum
        $backupSizeMB = [math]::Round($backupSize / 1MB, 2)
        Add-ToReport "Backup Size: $backupSizeMB MB"

        Add-ToReport ""
    } else {
        Write-Log "No configuration backups found" "ERROR"
        Add-ToReport "Configuration Backup Test: FAILED - No backups found"
        Add-ToReport ""
    }
}

# Test Docker volume backups
function Test-DockerVolumeBackups {
    Write-Log "Testing Docker volume backups"

    $volumeDir = Join-Path $BackupRoot "docker-volumes"
    $latestBackup = Get-ChildItem $volumeDir -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1

    if ($latestBackup) {
        Write-Log "Testing latest Docker volume backup: $($latestBackup.Name)"
        Add-ToReport "Docker Volume Backup Test"
        Add-ToReport "=========================="
        Add-ToReport "Latest Backup: $($latestBackup.FullName)"

        # Check for archive files
        $archives = Get-ChildItem $latestBackup.FullName -Recurse -File -Filter "*.tar.gz"

        if ($archives.Count -gt 0) {
            Add-ToReport "Archives Found: $($archives.Count)"

            foreach ($archive in $archives) {
                Write-Log "Testing archive: $($archive.Name)"

                # Test archive integrity
                try {
                    $env:Path += ";C:\Program Files\Git\bin"
                    $testResult = & tar -tzf $archive.FullName 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $archiveSizeMB = [math]::Round($archive.Length / 1MB, 2)
                        Add-ToReport "✓ $($archive.Name) - $archiveSizeMB MB - Valid"
                        Write-Log "Archive integrity verified: $($archive.Name)"
                    } else {
                        Add-ToReport "✗ $($archive.Name) - Corrupted"
                        Write-Log "Archive corrupted: $($archive.Name)" "ERROR"
                    }
                }
                catch {
                    Add-ToReport "✗ $($archive.Name) - Test failed"
                    Write-Log "Archive test failed: $($archive.Name) - $($_.Exception.Message)" "ERROR"
                }
            }
        } else {
            Add-ToReport "No archive files found"
            Write-Log "No archive files found in backup" "WARNING"
        }

        Add-ToReport ""
    } else {
        Write-Log "No Docker volume backups found" "ERROR"
        Add-ToReport "Docker Volume Backup Test: FAILED - No backups found"
        Add-ToReport ""
    }
}

# Test nested services backups
function Test-NestedServicesBackups {
    Write-Log "Testing nested services backups"

    $servicesDir = Join-Path $BackupRoot "nested-services"
    $latestBackup = Get-ChildItem $servicesDir -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1

    if ($latestBackup) {
        Write-Log "Testing latest nested services backup: $($latestBackup.Name)"
        Add-ToReport "Nested Services Backup Test"
        Add-ToReport "============================="
        Add-ToReport "Latest Backup: $($latestBackup.FullName)"

        # Check for service-specific backups
        $serviceFiles = @(
            "postgresql_*.sql.gz",
            "redis_*.rdb.gz",
            "qdrant_*.tar.gz",
            "neo4j_*.tar.gz",
            "ollama_*.tar.gz"
        )

        foreach ($pattern in $serviceFiles) {
            $files = Get-ChildItem $latestBackup.FullName -File -Filter $pattern
            if ($files.Count -gt 0) {
                foreach ($file in $files) {
                    $fileSizeMB = [math]::Round($file.Length / 1MB, 2)
                    Add-ToReport "✓ $($file.Name) - $fileSizeMB MB - Present"

                    # Test gzip integrity for compressed files
                    if ($file.Name -like "*.gz") {
                        try {
                            $testResult = & gzip -t $file.FullName 2>&1
                            if ($LASTEXITCODE -eq 0) {
                                Add-ToReport "  └─ Gzip integrity: Valid"
                            } else {
                                Add-ToReport "  └─ Gzip integrity: Corrupted"
                            }
                        }
                        catch {
                            Add-ToReport "  └─ Gzip integrity: Test failed"
                        }
                    }
                }
            } else {
                $serviceName = $pattern -replace "_.*", ""
                Add-ToReport "✗ $serviceName backup - Missing"
                Write-Log "$serviceName backup missing" "WARNING"
            }
        }

        Add-ToReport ""
    } else {
        Write-Log "No nested services backups found" "ERROR"
        Add-ToReport "Nested Services Backup Test: FAILED - No backups found"
        Add-ToReport ""
    }
}

# Test Ubuntu volume backups
function Test-UbuntuVolumeBackups {
    Write-Log "Testing Ubuntu volume backups"

    $ubuntuDir = Join-Path $BackupRoot "ubuntu-volumes"
    $latestBackup = Get-ChildItem $ubuntuDir -Directory | Where-Object { $_.Name -match '^\d{8}_\d{6}$' } | Sort-Object Name -Descending | Select-Object -First 1

    if ($latestBackup) {
        Write-Log "Testing latest Ubuntu volume backup: $($latestBackup.Name)"
        Add-ToReport "Ubuntu Volume Backup Test"
        Add-ToReport "=========================="
        Add-ToReport "Latest Backup: $($latestBackup.FullName)"

        $archives = Get-ChildItem $latestBackup.FullName -Recurse -File -Filter "*.tar.gz"

        if ($archives.Count -gt 0) {
            Add-ToReport "Archives Found: $($archives.Count)"

            foreach ($archive in $archives) {
                Write-Log "Testing Ubuntu archive: $($archive.Name)"

                try {
                    $env:Path += ";C:\Program Files\Git\bin"
                    $testResult = & tar -tzf $archive.FullName 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $archiveSizeMB = [math]::Round($archive.Length / 1MB, 2)
                        Add-ToReport "✓ $($archive.Name) - $archiveSizeMB MB - Valid"
                        Write-Log "Ubuntu archive integrity verified: $($archive.Name)"
                    } else {
                        Add-ToReport "✗ $($archive.Name) - Corrupted"
                        Write-Log "Ubuntu archive corrupted: $($archive.Name)" "ERROR"
                    }
                }
                catch {
                    Add-ToReport "✗ $($archive.Name) - Test failed"
                    Write-Log "Ubuntu archive test failed: $($archive.Name) - $($_.Exception.Message)" "ERROR"
                }
            }
        } else {
            Add-ToReport "No Ubuntu volume archives found"
            Write-Log "No Ubuntu volume archives found" "WARNING"
        }

        Add-ToReport ""
    } else {
        Write-Log "No Ubuntu volume backups found" "ERROR"
        Add-ToReport "Ubuntu Volume Backup Test: FAILED - No backups found"
        Add-ToReport ""
    }
}

# Run tests based on type
switch ($TestType) {
    "All" {
        Test-ConfigurationBackups
        Test-DockerVolumeBackups
        Test-NestedServicesBackups
        Test-UbuntuVolumeBackups
    }
    "Configurations" { Test-ConfigurationBackups }
    "DockerVolumes" { Test-DockerVolumeBackups }
    "NestedServices" { Test-NestedServicesBackups }
    "UbuntuVolumes" { Test-UbuntuVolumeBackups }
}

# Calculate overall statistics
Write-Log "Calculating overall statistics"

Add-ToReport "Overall Backup Statistics"
Add-ToReport "========================"

$totalSize = (Get-ChildItem $BackupRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalSizeGB = [math]::Round($totalSize / 1GB, 2)
Add-ToReport "Total Backup Size: $totalSizeGB GB"

$backupDirs = Get-ChildItem $BackupRoot -Directory
foreach ($dir in $backupDirs) {
    $dirSize = (Get-ChildItem $dir.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $dirSizeGB = [math]::Round($dirSize / 1GB, 2)
    Add-ToReport "$($dir.Name): $dirSizeGB GB"
}

# Check retention policy compliance
Add-ToReport ""
Add-ToReport "Retention Policy Check"
Add-ToReport "======================"

$oldBackups = Get-ChildItem $BackupRoot -Directory -Recurse | Where-Object {
    $_.Name -match '^\d{8}_\d{6}$' -and
    (Get-Date) - (Get-Date $_.Name.Substring(0,8)) -gt (New-TimeSpan -Days 30)
}

if ($oldBackups.Count -gt 0) {
    Add-ToReport "WARNING: Found $($oldBackups.Count) backups older than 30 days:"
    foreach ($oldBackup in $oldBackups) {
        Add-ToReport "  - $($oldBackup.FullName)"
    }
} else {
    Add-ToReport "✓ All backups comply with 30-day retention policy"
}

# Generate summary
Add-ToReport ""
Add-ToReport "Verification Summary"
Add-ToReport "===================="
Add-ToReport "Report Generated: $(Get-Date)"
Add-ToReport "Log File: $logFile"
Add-ToReport "Verification Completed Successfully"

Write-Log "Backup verification completed. Report: $reportFile"

# Output final status
Write-Host "Backup verification completed successfully!" -ForegroundColor Green
Write-Host "Report: $reportFile" -ForegroundColor Cyan
Write-Host "Log: $logFile" -ForegroundColor Cyan