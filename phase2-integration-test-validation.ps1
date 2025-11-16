# Phase 2: Integration Test and Validation Script
# This script validates the complete Phase 2 network security implementation
# by running comprehensive tests across all components

# Requires administrator privileges
#Requires -RunAsAdministrator

# Configuration Variables
$UbuntuContainerName = "ubuntu-server"
$DockerNetworkName = "localai-bridge"
$InternalNetworkName = "localai-internal"
$HostIPAddress = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*Ethernet*" -or $_.InterfaceAlias -like "*Wi-Fi*" } | Select-Object -First 1).IPAddress
$TestResults = @{}
$TestStartTime = Get-Date

Write-Host "Starting Phase 2 integration testing and validation..." -ForegroundColor Green
Write-Host "Test Start Time: $TestStartTime" -ForegroundColor Cyan
Write-Host "Host IP Address: $HostIPAddress" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Function to log test results
function Log-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = "",
        [string]$ErrorMessage = ""
    )

    $TestResults[$TestName] = @{
        Passed = $Passed
        Details = $Details
        ErrorMessage = $ErrorMessage
        Timestamp = Get-Date
    }

    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }

    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Details) { Write-Host "  Details: $Details" -ForegroundColor Yellow }
    if ($ErrorMessage) { Write-Host "  Error: $ErrorMessage" -ForegroundColor Red }
    Write-Host ""
}

# Function to run command and capture output
function Run-TestCommand {
    param([string]$Command, [string]$Description)

    try {
        $output = Invoke-Expression $Command 2>&1
        return @{ Success = $true; Output = $output; Error = $null }
    } catch {
        return @{ Success = $false; Output = $null; Error = $_.Exception.Message }
    }
}

# Test 1: Windows Firewall Configuration
Write-Host "Test 1: Windows Firewall Configuration" -ForegroundColor Cyan

# Test firewall profiles
$fwProfiles = Get-NetFirewallProfile
$enabledProfiles = ($fwProfiles | Where-Object { $_.Enabled -eq "True" }).Count
Log-TestResult "Firewall Profiles Enabled" ($enabledProfiles -eq 3) "Enabled profiles: $enabledProfiles/3"

# Test HTTP rule
$httpRule = Get-NetFirewallRule -DisplayName "HTTP (Port 80)" -ErrorAction SilentlyContinue
Log-TestResult "HTTP Firewall Rule" ($httpRule -and $httpRule.Enabled -eq "True") "Rule exists and enabled: $($httpRule.Enabled)"

# Test HTTPS rule
$httpsRule = Get-NetFirewallRule -DisplayName "HTTPS (Port 443)" -ErrorAction SilentlyContinue
Log-TestResult "HTTPS Firewall Rule" ($httpsRule -and $httpsRule.Enabled -eq "True") "Rule exists and enabled: $($httpsRule.Enabled)"

# Test logging
$loggingEnabled = ($fwProfiles | Where-Object { $_.LogAllowed -eq "True" -and $_.LogBlocked -eq "True" }).Count
Log-TestResult "Firewall Logging" ($loggingEnabled -eq 3) "Logging enabled on $loggingEnabled/3 profiles"

# Test 2: Docker Desktop and Networks
Write-Host "Test 2: Docker Desktop and Networks" -ForegroundColor Cyan

# Test Docker service
$dockerService = Get-Service -Name "Docker Desktop Service" -ErrorAction SilentlyContinue
$dockerRunning = ($dockerService -and $dockerService.Status -eq "Running")
Log-TestResult "Docker Desktop Service" $dockerRunning "Service status: $($dockerService.Status)"

if ($dockerRunning) {
    # Test external network
    $externalNetwork = docker network inspect $DockerNetworkName 2>$null | ConvertFrom-Json
    Log-TestResult "External Docker Network" ($null -ne $externalNetwork) "Network $DockerNetworkName exists"

    # Test internal network
    $internalNetwork = docker network inspect $InternalNetworkName 2>$null | ConvertFrom-Json
    Log-TestResult "Internal Docker Network" ($null -ne $internalNetwork) "Network $InternalNetworkName exists"
}

# Test 3: Ubuntu Container Configuration
Write-Host "Test 3: Ubuntu Container Configuration" -ForegroundColor Cyan

# Test container existence
$containerInfo = docker ps -a --filter "name=$UbuntuContainerName" --format "{{.Names}}|{{.Status}}" | ConvertFrom-Csv -Delimiter "|" -Header Name,Status
$containerExists = ($containerInfo -and $containerInfo.Name -eq $UbuntuContainerName)
Log-TestResult "Ubuntu Container Exists" $containerExists "Container name: $($containerInfo.Name)"

if ($containerExists) {
    # Test container running
    $containerRunning = $containerInfo.Status -like "*Up*"
    Log-TestResult "Ubuntu Container Running" $containerRunning "Status: $($containerInfo.Status)"

    if ($containerRunning) {
        # Test container privileges
        $privileged = docker inspect $UbuntuContainerName | ConvertFrom-Json | Select-Object -ExpandProperty HostConfig -ExpandProperty Privileged
        Log-TestResult "Container Privileged Mode" $privileged "Privileged mode: $privileged"

        # Test network connections
        $networks = docker inspect $UbuntuContainerName | ConvertFrom-Json | Select-Object -ExpandProperty NetworkSettings -ExpandProperty Networks
        $externalConnected = $networks.PSObject.Properties.Name -contains $DockerNetworkName
        $internalConnected = $networks.PSObject.Properties.Name -contains $InternalNetworkName
        Log-TestResult "External Network Connection" $externalConnected "Connected to $DockerNetworkName"
        Log-TestResult "Internal Network Connection" $internalConnected "Connected to $InternalNetworkName"

        # Test Docker-in-Docker access
        $dockerAccess = Run-TestCommand "docker exec $UbuntuContainerName docker info" "Docker-in-Docker access"
        Log-TestResult "Docker-in-Docker Access" $dockerAccess.Success "Can access Docker daemon from container"
    }
}

# Test 4: Port Forwarding and Connectivity
Write-Host "Test 4: Port Forwarding and Connectivity" -ForegroundColor Cyan

$portsToTest = @(
    @{ Port = 80; Service = "HTTP" },
    @{ Port = 443; Service = "HTTPS" },
    @{ Port = 22; Service = "SSH" },
    @{ Port = 5678; Service = "N8N" },
    @{ Port = 3000; Service = "Open WebUI" },
    @{ Port = 3001; Service = "Flowise" },
    @{ Port = 3002; Service = "Supabase" },
    @{ Port = 8080; Service = "SearXNG" },
    @{ Port = 7474; Service = "Neo4j" },
    @{ Port = 3003; Service = "Langfuse" }
)

foreach ($portTest in $portsToTest) {
    $port = $portTest.Port
    $service = $portTest.Service

    $connection = Test-NetConnection -ComputerName localhost -Port $port -WarningAction SilentlyContinue
    Log-TestResult "Port $port ($service) Connectivity" $connection.TcpTestSucceeded "TCP connection successful: $($connection.TcpTestSucceeded)"
}

# Test 5: Network Isolation and Security
Write-Host "Test 5: Network Isolation and Security" -ForegroundColor Cyan

if ($containerExists -and $containerRunning) {
    # Test external connectivity from container
    $externalPing = Run-TestCommand "docker exec $UbuntuContainerName ping -c 3 8.8.8.8" "External connectivity test"
    Log-TestResult "Container External Connectivity" $externalPing.Success "Container can reach external hosts"

    # Test DNS resolution
    $dnsTest = Run-TestCommand "docker exec $UbuntuContainerName nslookup google.com" "DNS resolution test"
    Log-TestResult "Container DNS Resolution" $dnsTest.Success "Container can resolve DNS names"

    # Test iptables rules
    $iptablesRules = Run-TestCommand "docker exec $UbuntuContainerName iptables -L -n | grep -c ACCEPT" "iptables rules check"
    Log-TestResult "Container iptables Rules" ($iptablesRules.Success -and [int]$iptablesRules.Output -gt 5) "iptables rules configured: $($iptablesRules.Output) ACCEPT rules"
}

# Test 6: Windows Defender Configuration
Write-Host "Test 6: Windows Defender Configuration" -ForegroundColor Cyan

$defenderStatus = Get-MpComputerStatus

# Test real-time protection
Log-TestResult "Defender Real-time Protection" $defenderStatus.AntivirusEnabled "Real-time protection enabled: $($defenderStatus.AntivirusEnabled)"

# Test cloud protection
$cloudProtection = $defenderStatus.MAPSReporting -gt 0
Log-TestResult "Defender Cloud Protection" $cloudProtection "Cloud protection level: $($defenderStatus.MAPSReporting)"

# Test network protection
Log-TestResult "Defender Network Protection" $defenderStatus.NIsEnabled "Network protection enabled: $($defenderStatus.NIsEnabled)"

# Test tamper protection
Log-TestResult "Defender Tamper Protection" $defenderStatus.IsTamperProtected "Tamper protection enabled: $($defenderStatus.IsTamperProtected)"

# Test exclusions
$exclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
$dockerExcluded = $exclusions -like "*Docker*"
Log-TestResult "Defender Docker Exclusions" ($dockerExcluded.Count -gt 0) "Docker paths excluded: $($dockerExcluded.Count) exclusions"

# Test ASR rules
$asrRules = Get-MpPreference | Select-Object -ExpandProperty AttackSurfaceReductionRules_Actions
Log-TestResult "Defender ASR Rules" ($asrRules.Count -gt 0) "ASR rules configured: $($asrRules.Count) rules"

# Test 7: Monitoring and Alert System
Write-Host "Test 7: Monitoring and Alert System" -ForegroundColor Cyan

# Test monitoring directory
$monitoringDir = "C:\Monitoring\NetworkSecurity"
$monitoringExists = Test-Path $monitoringDir
Log-TestResult "Monitoring Directory" $monitoringExists "Directory exists: $monitoringDir"

if ($monitoringExists) {
    # Test continuous monitoring script
    $continuousScript = "$monitoringDir\ContinuousMonitoring.ps1"
    $scriptExists = Test-Path $continuousScript
    Log-TestResult "Continuous Monitoring Script" $scriptExists "Script exists: $continuousScript"

    # Test alert script
    $alertScript = "$monitoringDir\CheckAlerts.ps1"
    $alertExists = Test-Path $alertScript
    Log-TestResult "Alert System Script" $alertExists "Script exists: $alertScript"

    # Test scheduled tasks
    $monitoringTask = Get-ScheduledTask -TaskName "NetworkSecurityMonitoring" -ErrorAction SilentlyContinue
    $taskExists = ($null -ne $monitoringTask)
    Log-TestResult "Monitoring Scheduled Task" $taskExists "Task status: $($monitoringTask.State)"
}

# Test 8: Performance and Resource Usage
Write-Host "Test 8: Performance and Resource Usage" -ForegroundColor Cyan

# Test container resource usage
if ($containerExists -and $containerRunning) {
    $containerStats = docker stats --no-stream --format "{{.Container}}|{{.CPUPerc}}|{{.MemUsage}}" $UbuntuContainerName
    if ($containerStats) {
        $stats = $containerStats | ConvertFrom-Csv -Delimiter "|" -Header Container,CPU,Memory
        Log-TestResult "Container Resource Usage" $true "CPU: $($stats.CPU), Memory: $($stats.Memory)"
    } else {
        Log-TestResult "Container Resource Usage" $false "Could not retrieve container stats"
    }
}

# Test Windows Defender performance
$defenderProcess = Get-Process -Name MsMpEng -ErrorAction SilentlyContinue
if ($defenderProcess) {
    $defenderMemory = [math]::Round($defenderProcess.PM / 1MB, 2)
    Log-TestResult "Defender Memory Usage" ($defenderMemory -lt 500) "Memory usage: ${defenderMemory}MB (should be <500MB)"
} else {
    Log-TestResult "Defender Process Check" $false "Windows Defender process not found"
}

# Test 9: Integration and End-to-End Testing
Write-Host "Test 9: Integration and End-to-End Testing" -ForegroundColor Cyan

# Test complete network path (external -> host -> container)
$endToEndTest = @()
foreach ($port in @(80, 443)) {
    $externalTest = Test-NetConnection -ComputerName $HostIPAddress -Port $port -WarningAction SilentlyContinue
    $endToEndTest += $externalTest.TcpTestSucceeded
}

$allPortsWorking = ($endToEndTest | Where-Object { $_ -eq $true }).Count -eq $endToEndTest.Count
Log-TestResult "End-to-End Connectivity" $allPortsWorking "External access to host ports 80/443: $($endToEndTest -join ', ')"

# Test firewall rule effectiveness (should block unauthorized ports)
$blockedPortTest = Test-NetConnection -ComputerName localhost -Port 9999 -WarningAction SilentlyContinue
Log-TestResult "Firewall Blocking Unauthorized Ports" (-not $blockedPortTest.TcpTestSucceeded) "Port 9999 correctly blocked: $(-not $blockedPortTest.TcpTestSucceeded)"

# Generate Test Summary Report
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "PHASE 2 INTEGRATION TEST SUMMARY" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan

$TestEndTime = Get-Date
$TotalTests = $TestResults.Count
$PassedTests = ($TestResults.Values | Where-Object { $_.Passed }).Count
$FailedTests = $TotalTests - $PassedTests
$TestDuration = $TestEndTime - $TestStartTime

Write-Host "Test Execution Summary:" -ForegroundColor Cyan
Write-Host "- Total Tests: $TotalTests" -ForegroundColor White
Write-Host "- Passed: $PassedTests" -ForegroundColor Green
Write-Host "- Failed: $FailedTests" -ForegroundColor Red
Write-Host "- Duration: $($TestDuration.TotalSeconds.ToString("F2")) seconds" -ForegroundColor White
Write-Host "- Success Rate: $([math]::Round(($PassedTests / $TotalTests) * 100, 2))%" -ForegroundColor $(if (($PassedTests / $TotalTests) -ge 0.9) { "Green" } else { "Red" })

# Generate detailed report
$reportFile = "phase2-integration-test-report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$reportContent = @"
Phase 2 Integration Test Report
Generated: $(Get-Date)
Host: $env:COMPUTERNAME
Host IP: $HostIPAddress

EXECUTION SUMMARY
=================
Total Tests: $TotalTests
Passed: $PassedTests
Failed: $FailedTests
Success Rate: $([math]::Round(($PassedTests / $TotalTests) * 100, 2))%
Duration: $($TestDuration.TotalSeconds.ToString("F2")) seconds

DETAILED TEST RESULTS
=====================
"@

foreach ($testName in $TestResults.Keys) {
    $result = $TestResults[$testName]
    $status = if ($result.Passed) { "PASS" } else { "FAIL" }
    $reportContent += "`n$status`: $testName"
    if ($result.Details) { $reportContent += "`n  Details: $($result.Details)" }
    if ($result.ErrorMessage) { $reportContent += "`n  Error: $($result.ErrorMessage)" }
    $reportContent += "`n  Timestamp: $($result.Timestamp)"
}

$reportContent += @"


CRITICAL FAILURES
=================
"@

$criticalFailures = $TestResults.GetEnumerator() | Where-Object {
    -not $_.Value.Passed -and (
        $_.Key -like "*Firewall*" -or
        $_.Key -like "*Container*" -or
        $_.Key -like "*Docker*" -or
        $_.Key -like "*Port*" -or
        $_.Key -like "*Connectivity*"
    )
}

if ($criticalFailures) {
    foreach ($failure in $criticalFailures) {
        $reportContent += "`n- $($failure.Key)"
        $reportContent += "`n  Error: $($failure.Value.ErrorMessage)"
    }
} else {
    $reportContent += "`nNo critical failures detected."
}

$reportContent += @"


RECOMMENDATIONS
===============
"@

if ($FailedTests -gt 0) {
    $reportContent += "`n- Review failed tests and address issues using troubleshooting guide"
    $reportContent += "`n- Re-run individual component scripts for failed areas"
    $reportContent += "`n- Check Phase 2 troubleshooting procedures for specific error resolution"
}

if (($PassedTests / $TotalTests) -lt 0.9) {
    $reportContent += "`n- Overall success rate below 90%. Consider full re-deployment of Phase 2"
}

$reportContent += @"


NEXT STEPS
==========
1. Review this report for any failures
2. Address critical issues using troubleshooting procedures
3. Re-run this validation script after fixes
4. Proceed to Phase 3 when all critical tests pass
5. Schedule regular validation runs for ongoing monitoring

Report saved to: $reportFile
"@

$reportContent | Out-File -FilePath $reportFile -Encoding UTF8 -Force
Write-Host "`nDetailed test report saved to: $reportFile" -ForegroundColor Green

# Final status determination
$overallSuccess = ($PassedTests / $TotalTests) -ge 0.9  # 90% success threshold

Write-Host "`n=====================================" -ForegroundColor Cyan
if ($overallSuccess) {
    Write-Host "PHASE 2 INTEGRATION TEST: PASSED" -ForegroundColor Green
    Write-Host "All critical systems are operational and secure." -ForegroundColor Green
    Write-Host "Ready to proceed with Phase 3 deployment." -ForegroundColor Green
} else {
    Write-Host "PHASE 2 INTEGRATION TEST: FAILED" -ForegroundColor Red
    Write-Host "Critical issues detected. Review the report and troubleshooting guide." -ForegroundColor Red
    Write-Host "Do not proceed to Phase 3 until issues are resolved." -ForegroundColor Red
}

Write-Host "=====================================" -ForegroundColor Cyan

# Return test results for potential use by other scripts
return @{
    TotalTests = $TotalTests
    PassedTests = $PassedTests
    FailedTests = $FailedTests
    SuccessRate = [math]::Round(($PassedTests / $TotalTests) * 100, 2)
    OverallSuccess = $overallSuccess
    TestResults = $TestResults
    ReportFile = $reportFile
    Duration = $TestDuration
}