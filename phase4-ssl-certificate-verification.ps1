# Phase 4: SSL/TLS Certificate Management - Certificate Verification Script
# This script verifies certificate installation, paths, and configuration

param(
    [Parameter(Mandatory=$false)]
    [switch]$Detailed,
    [Parameter(Mandatory=$false)]
    [switch]$Quiet
)

# Configuration
$DOMAIN = "supersmartinnovations.cloud"
$CERT_PATH = "/etc/letsencrypt/live/$DOMAIN"
$LETSENCRYPT_DIR = Join-Path $PSScriptRoot "letsencrypt"

# Colors for output
$Green = "Green"
$Yellow = "Yellow"
$Red = "Red"
$Cyan = "Cyan"
$White = "White"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$QuietOverride
    )

    if ($Quiet -and -not $QuietOverride) {
        return
    }

    Write-Host $Message -ForegroundColor $Color
}

function Write-Status {
    param(
        [string]$Test,
        [string]$Status,
        [string]$Details = "",
        [switch]$QuietOverride
    )

    $statusColor = switch ($Status) {
        "PASS" { $Green }
        "FAIL" { $Red }
        "WARN" { $Yellow }
        default { $White }
    }

    if ($Quiet) {
        if ($Status -eq "FAIL" -or $QuietOverride) {
            Write-Host "$Test : $Status" -ForegroundColor $statusColor
            if ($Details) {
                Write-Host "  $Details" -ForegroundColor $White
            }
        }
    } else {
        Write-Host "$Test : " -NoNewline
        Write-Host $Status -ForegroundColor $statusColor -NoNewline
        if ($Details) {
            Write-Host " - $Details" -ForegroundColor $White
        } else {
            Write-Host ""
        }
    }
}

Write-ColorOutput "=================================" $Cyan
Write-ColorOutput "SSL Certificate Verification" $Cyan
Write-ColorOutput "=================================" $Cyan

$allPassed = $true
$testsRun = 0
$testsPassed = 0

# Test 1: Check Docker is running
$testsRun++
try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Docker connectivity" "PASS" "Version: $dockerVersion"
        $testsPassed++
    } else {
        Write-Status "Docker connectivity" "FAIL" "Docker not running or accessible"
        $allPassed = $false
    }
} catch {
    Write-Status "Docker connectivity" "FAIL" "Error: $($_.Exception.Message)"
    $allPassed = $false
}

# Test 2: Check certificate directory exists
$testsRun++
if (Test-Path $LETSENCRYPT_DIR) {
    Write-Status "Certificate directory" "PASS" "Path: $LETSENCRYPT_DIR"
    $testsPassed++
} else {
    Write-Status "Certificate directory" "FAIL" "Directory not found: $LETSENCRYPT_DIR"
    $allPassed = $false
}

# Test 3: Check certificate files exist
$testsRun++
$certFiles = @("cert.pem", "chain.pem", "fullchain.pem", "privkey.pem")
$missingFiles = @()

foreach ($file in $certFiles) {
    $filePath = Join-Path $LETSENCRYPT_DIR $file
    if (-not (Test-Path $filePath)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -eq 0) {
    Write-Status "Certificate files" "PASS" "All files present"
    $testsPassed++
} else {
    Write-Status "Certificate files" "FAIL" "Missing: $($missingFiles -join ', ')"
    $allPassed = $false
}

# Test 4: Verify certificate content
$testsRun++
$certPath = Join-Path $LETSENCRYPT_DIR "cert.pem"
if (Test-Path $certPath) {
    try {
        $certInfo = & openssl x509 -in $certPath -text -noout 2>$null
        if ($LASTEXITCODE -eq 0) {
            # Check subject
            $subject = ($certInfo | Select-String -Pattern "Subject:").Line
            if ($subject -match "supersmartinnovations\.cloud") {
                Write-Status "Certificate subject" "PASS" "Valid domain found"
                $testsPassed++
            } else {
                Write-Status "Certificate subject" "FAIL" "Domain not found in certificate"
                $allPassed = $false
            }

            # Check expiry
            $expiryLine = ($certInfo | Select-String -Pattern "Not After :").Line
            if ($expiryLine) {
                $expiryDate = ($expiryLine -replace "Not After : ", "").Trim()
                try {
                    $expiry = [DateTime]::Parse($expiryDate)
                    $daysUntilExpiry = ($expiry - (Get-Date)).Days

                    if ($daysUntilExpiry -gt 30) {
                        Write-Status "Certificate expiry" "PASS" "$daysUntilExpiry days remaining"
                        $testsPassed++
                    } elseif ($daysUntilExpiry -gt 7) {
                        Write-Status "Certificate expiry" "WARN" "$daysUntilExpiry days remaining"
                        $testsPassed++
                    } else {
                        Write-Status "Certificate expiry" "FAIL" "$daysUntilExpiry days remaining"
                        $allPassed = $false
                    }
                } catch {
                    Write-Status "Certificate expiry" "FAIL" "Could not parse date: $expiryDate"
                    $allPassed = $false
                }
            } else {
                Write-Status "Certificate expiry" "FAIL" "Expiry date not found"
                $allPassed = $false
            }

            # Check SAN (Subject Alternative Names)
            $sanSection = $certInfo | Select-String -Pattern "DNS:" -Context 0,10
            $domainsFound = @()
            foreach ($line in $sanSection) {
                $dnsMatches = [regex]::Matches($line, "DNS:([^,\s]+)")
                foreach ($match in $dnsMatches) {
                    $domainsFound += $match.Groups[1].Value
                }
            }

            $expectedDomains = @("supersmartinnovations.cloud", "*.supersmartinnovations.cloud")
            $missingDomains = @()
            foreach ($domain in $expectedDomains) {
                if ($domain -notin $domainsFound) {
                    $missingDomains += $domain
                }
            }

            if ($missingDomains.Count -eq 0) {
                Write-Status "Certificate SAN" "PASS" "All domains covered"
                $testsPassed++
            } else {
                Write-Status "Certificate SAN" "FAIL" "Missing domains: $($missingDomains -join ', ')"
                $allPassed = $false
            }
        } else {
            Write-Status "Certificate verification" "FAIL" "Could not read certificate"
            $allPassed = $false
        }
    } catch {
        Write-Status "Certificate verification" "FAIL" "Error reading certificate: $($_.Exception.Message)"
        $allPassed = $false
    }
} else {
    Write-Status "Certificate verification" "FAIL" "Certificate file not found"
    $allPassed = $false
    $testsRun += 3  # Account for the skipped sub-tests
}

# Test 5: Check Docker Compose configuration
$testsRun++
$composeFile = Join-Path $PSScriptRoot "docker-compose.yml"
if (Test-Path $composeFile) {
    $composeContent = Get-Content $composeFile -Raw
    if ($composeContent -match "letsencrypt-certs:") {
        Write-Status "Docker Compose volume" "PASS" "letsencrypt-certs volume configured"
        $testsPassed++
    } else {
        Write-Status "Docker Compose volume" "FAIL" "letsencrypt-certs volume not found"
        $allPassed = $false
    }

    if ($composeContent -match "\./letsencrypt:/etc/letsencrypt:ro") {
        Write-Status "Certificate mounting" "PASS" "Certificates mounted in Caddy"
        $testsPassed++
    } else {
        Write-Status "Certificate mounting" "FAIL" "Certificate mount not found in Caddy config"
        $allPassed = $false
    }
} else {
    Write-Status "Docker Compose config" "FAIL" "docker-compose.yml not found"
    $allPassed = $false
    $testsRun++  # Account for skipped mount test
}

# Test 6: Check Caddyfile configuration
$testsRun++
$caddyFile = Join-Path $PSScriptRoot "Caddyfile"
if (Test-Path $caddyFile) {
    $caddyContent = Get-Content $caddyFile -Raw
    $sslConfigs = [regex]::Matches($caddyContent, "tls /etc/letsencrypt/live/supersmartinnovations\.cloud/fullchain\.pem /etc/letsencrypt/live/supersmartinnovations\.cloud/privkey\.pem")

    if ($sslConfigs.Count -gt 0) {
        Write-Status "Caddy SSL config" "PASS" "$($sslConfigs.Count) SSL configurations found"
        $testsPassed++
    } else {
        Write-Status "Caddy SSL config" "FAIL" "No SSL configurations found"
        $allPassed = $false
    }
} else {
    Write-Status "Caddyfile config" "FAIL" "Caddyfile not found"
    $allPassed = $false
}

# Test 7: Check environment variables
$testsRun++
$envExample = Join-Path $PSScriptRoot ".env.production.example"
if (Test-Path $envExample) {
    $envContent = Get-Content $envExample -Raw
    $sslVars = @("LETSENCRYPT_EMAIL", "CLOUDFLARE_EMAIL", "CLOUDFLARE_API_KEY")
    $missingVars = @()

    foreach ($var in $sslVars) {
        if ($envContent -notmatch "$var=") {
            $missingVars += $var
        }
    }

    if ($missingVars.Count -eq 0) {
        Write-Status "Environment variables" "PASS" "All SSL variables configured"
        $testsPassed++
    } else {
        Write-Status "Environment variables" "FAIL" "Missing: $($missingVars -join ', ')"
        $allPassed = $false
    }
} else {
    Write-Status "Environment template" "FAIL" ".env.production.example not found"
    $allPassed = $false
}

# Test 8: Check monitoring scripts
$testsRun++
$monitoringScripts = @(
    "phase4-certificate-renewal-monitoring.sh",
    "phase4-ssl-certificate-orchestration.ps1",
    "phase4-certbot-certificate-generation.sh"
)

$missingScripts = @()
foreach ($script in $monitoringScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    if (-not (Test-Path $scriptPath)) {
        $missingScripts += $script
    }
}

if ($missingScripts.Count -eq 0) {
    Write-Status "Monitoring scripts" "PASS" "All scripts present"
    $testsPassed++
} else {
    Write-Status "Monitoring scripts" "FAIL" "Missing: $($missingScripts -join ', ')"
    $allPassed = $false
}

# Summary
Write-ColorOutput ""
Write-ColorOutput "=================================" $Cyan
Write-ColorOutput "VERIFICATION SUMMARY" $Cyan
Write-ColorOutput "=================================" $Cyan

$passColor = if ($allPassed) { $Green } else { $Red }
Write-ColorOutput "Tests Run: $testsRun" $White
Write-ColorOutput "Tests Passed: $testsPassed" $passColor
Write-ColorOutput "Tests Failed: $($testsRun - $testsPassed)" $(if ($testsRun - $testsPassed -gt 0) { $Red } else { $Green })

if ($allPassed) {
    Write-ColorOutput "Overall Status: PASS" $Green
    Write-ColorOutput "SSL certificate management is properly configured!" $Green
} else {
    Write-ColorOutput "Overall Status: FAIL" $Red
    Write-ColorOutput "Some SSL certificate components are misconfigured." $Red
    Write-ColorOutput "Please review the failed tests above and correct the issues." $Yellow
}

Write-ColorOutput "=================================" $Cyan

# Detailed output if requested
if ($Detailed) {
    Write-ColorOutput ""
    Write-ColorOutput "Detailed Certificate Information:" $Cyan
    if (Test-Path $certPath) {
        try {
            $certDetails = & openssl x509 -in $certPath -text -noout 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "Certificate Details:" $White
                Write-ColorOutput "$certDetails" $White
            }
        } catch {
            Write-ColorOutput "Could not read detailed certificate information." $Yellow
        }
    } else {
        Write-ColorOutput "Certificate file not found for detailed analysis." $Yellow
    }
}

# Return appropriate exit code
if ($allPassed) {
    exit 0
} else {
    exit 1
}