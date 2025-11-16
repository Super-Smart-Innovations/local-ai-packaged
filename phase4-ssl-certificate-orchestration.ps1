# Phase 4: SSL/TLS Certificate Management - PowerShell Orchestration Script
# This script handles certificate generation orchestration and DNS challenge management

param(
    [Parameter(Mandatory=$false)]
    [string]$CloudflareEmail,

    [Parameter(Mandatory=$false)]
    [string]$CloudflareApiKey,

    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
)

# Configuration
$DOMAIN = "supersmartinnovations.cloud"
$WILDCARD_DOMAIN = "*.supersmartinnovations.cloud"
$EMAIL = "admin@supersmartinnovations.cloud"
$CERT_PATH = "/etc/letsencrypt/live/$DOMAIN"
$CONTAINER_NAME = "certbot-generator"
$UBUNTU_IMAGE = "ubuntu:22.04"

# Colors for output
$Green = "Green"
$Yellow = "Yellow"
$Red = "Red"
$Cyan = "Cyan"

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "=================================" $Cyan
Write-ColorOutput "SSL Certificate Orchestration Script" $Cyan
Write-ColorOutput "Domain: $DOMAIN" $Cyan
Write-ColorOutput "Wildcard: $WILDCARD_DOMAIN" $Cyan
Write-ColorOutput "=================================" $Cyan

# Check if Docker is running
try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker is not running or not accessible"
    }
    Write-ColorOutput "Docker version: $dockerVersion" $Green
} catch {
    Write-ColorOutput "ERROR: Docker is not available. Please start Docker Desktop." $Red
    exit 1
}

# Get Cloudflare credentials if not provided
if (-not $CloudflareEmail) {
    $CloudflareEmail = Read-Host "Enter your Cloudflare email"
}
if (-not $CloudflareApiKey) {
    $CloudflareApiKey = Read-Host "Enter your Cloudflare API key" -AsSecureString
    $CloudflareApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($CloudflareApiKey))
}

# Create temporary directory for certificates
$TEMP_DIR = "$env:TEMP\letsencrypt-certs"
if (Test-Path $TEMP_DIR) {
    Remove-Item $TEMP_DIR -Recurse -Force
}
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

Write-ColorOutput "Created temporary directory: $TEMP_DIR" $Green

# Copy the certificate generation script to temp directory
$SCRIPT_PATH = Join-Path $PSScriptRoot "phase4-certbot-certificate-generation.sh"
if (-not (Test-Path $SCRIPT_PATH)) {
    Write-ColorOutput "ERROR: Certificate generation script not found at $SCRIPT_PATH" $Red
    exit 1
}

Copy-Item $SCRIPT_PATH (Join-Path $TEMP_DIR "certbot-generate.sh")

# Build Docker command
$dockerArgs = @(
    "run",
    "--rm",
    "--name", $CONTAINER_NAME,
    "-v", "${TEMP_DIR}:/scripts",
    "-v", "${TEMP_DIR}:/etc/letsencrypt",
    "-e", "CLOUDFLARE_EMAIL=$CloudflareEmail",
    "-e", "CLOUDFLARE_API_KEY=$CloudflareApiKey",
    $UBUNTU_IMAGE,
    "bash", "/scripts/certbot-generate.sh"
)

Write-ColorOutput "Starting certificate generation container..." $Yellow
Write-ColorOutput "Command: docker $($dockerArgs -join ' ')" $Cyan

try {
    # Run the certificate generation
    $output = & docker $dockerArgs 2>&1
    $exitCode = $LASTEXITCODE

    Write-ColorOutput "Container output:" $Cyan
    $output | ForEach-Object { Write-ColorOutput "  $_" }

    if ($exitCode -eq 0) {
        Write-ColorOutput "SUCCESS: Certificate generation completed!" $Green
    } else {
        Write-ColorOutput "ERROR: Certificate generation failed with exit code $exitCode" $Red
        exit 1
    }
} catch {
    Write-ColorOutput "ERROR: Failed to run Docker container: $($_.Exception.Message)" $Red
    exit 1
}

# Verify certificate files
if (-not $SkipVerification) {
    Write-ColorOutput "Verifying generated certificates..." $Yellow

    $certFiles = @(
        "cert.pem",
        "chain.pem",
        "fullchain.pem",
        "privkey.pem"
    )

    $allFilesExist = $true
    foreach ($file in $certFiles) {
        $filePath = Join-Path $TEMP_DIR $file
        if (Test-Path $filePath) {
            Write-ColorOutput "✓ Found $file" $Green
        } else {
            Write-ColorOutput "✗ Missing $file" $Red
            $allFilesExist = $false
        }
    }

    if ($allFilesExist) {
        Write-ColorOutput "All certificate files generated successfully!" $Green

        # Display certificate information
        $certPath = Join-Path $TEMP_DIR "cert.pem"
        if (Test-Path $certPath) {
            Write-ColorOutput "Certificate details:" $Cyan
            try {
                $certInfo = & openssl x509 -in $certPath -text -noout 2>$null
                if ($LASTEXITCODE -eq 0) {
                    ($certInfo | Select-String -Pattern "(Subject:|Issuer:|Not Before:|Not After :|DNS:)").Line | ForEach-Object {
                        Write-ColorOutput "  $_" $Cyan
                    }
                }
            } catch {
                Write-ColorOutput "Could not read certificate details (openssl not available)" $Yellow
            }
        }
    } else {
        Write-ColorOutput "ERROR: Some certificate files are missing!" $Red
        exit 1
    }
}

# Copy certificates to project directory for Docker volume mounting
$PROJECT_CERT_DIR = Join-Path $PSScriptRoot "letsencrypt"
if (-not (Test-Path $PROJECT_CERT_DIR)) {
    New-Item -ItemType Directory -Path $PROJECT_CERT_DIR -Force | Out-Null
}

Write-ColorOutput "Copying certificates to project directory..." $Yellow
Copy-Item "$TEMP_DIR\*" $PROJECT_CERT_DIR -Force

# Create .gitignore to prevent accidental commit of private keys
$gitignorePath = Join-Path $PROJECT_CERT_DIR ".gitignore"
if (-not (Test-Path $gitignorePath)) {
    @"
# Let's Encrypt certificates
*
!.gitignore
"@ | Out-File -FilePath $gitignorePath -Encoding UTF8
    Write-ColorOutput "Created .gitignore for certificate directory" $Green
}

Write-ColorOutput "Certificates copied to: $PROJECT_CERT_DIR" $Green

# Clean up temporary directory
Write-ColorOutput "Cleaning up temporary files..." $Yellow
Remove-Item $TEMP_DIR -Recurse -Force

Write-ColorOutput "=================================" $Cyan
Write-ColorOutput "Certificate orchestration completed!" $Green
Write-ColorOutput "Certificates are ready for Docker volume mounting." $Green
Write-ColorOutput "Next steps:" $Cyan
Write-ColorOutput "  1. Update docker-compose.yml to mount certificate volumes" $Cyan
Write-ColorOutput "  2. Update Caddyfile with SSL configuration" $Cyan
Write-ColorOutput "  3. Restart services to apply SSL configuration" $Cyan
Write-ColorOutput "=================================" $Cyan