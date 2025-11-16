# Phase 5: External Monitoring Services Setup
# This script configures UptimeRobot, Windows Event Logs, Grafana + Prometheus, and ELK stack

param(
    [switch]$SetupUptimeRobot,
    [switch]$SetupWindowsEventLogs,
    [switch]$SetupGrafanaPrometheus,
    [switch]$SetupELK,
    [string]$Domain = "yourdomain.com",
    [string[]]$Subdomains = @("www", "api", "n8n", "webui"),
    [string]$BaseLogPath = "C:\Logs\localai"
)

# Function to configure UptimeRobot monitoring
function Set-UptimeRobotMonitoring {
    param([string]$Domain, [string[]]$Subdomains)

    Write-Host "Configuring UptimeRobot monitoring..." -ForegroundColor Green

    $uptimeRobotConfig = @"
# UptimeRobot Monitoring Configuration
# Create monitors for the following endpoints:

Monitor Configuration:
"@

    # Generate monitor URLs
    $monitors = @()
    foreach ($subdomain in $Subdomains) {
        if ($subdomain -eq "www") {
            $monitors += "https://$Domain"
        } else {
            $monitors += "https://$subdomain.$Domain"
        }
    }

    # Add localhost monitoring for development
    $monitors += "http://localhost:5678"  # n8n
    $monitors += "http://localhost:3000"  # Open WebUI
    $monitors += "http://localhost:3001"  # Flowise

    foreach ($monitor in $monitors) {
        $uptimeRobotConfig += "`n- URL: $monitor`n  Monitor Type: HTTP(S)`n  Monitoring Interval: 5 minutes`n  Monitor Timeout: 30 seconds`n"
    }

    $configPath = "$BaseLogPath\uptime-robot-config.txt"
    $uptimeRobotConfig | Out-File -FilePath $configPath -Encoding UTF8

    Write-Host "UptimeRobot configuration created: $configPath"
    Write-Host "Please create monitors in UptimeRobot dashboard using the URLs above."
}

# Function to set up Windows Event Logs with comprehensive logging
function Set-WindowsEventLogs {
    Write-Host "Setting up Windows Event Logs..." -ForegroundColor Green

    # Create custom event sources
    $eventSources = @(
        "LocalAI-Services",
        "LocalAI-Monitoring",
        "LocalAI-Alerts",
        "LocalAI-Security",
        "LocalAI-Performance"
    )

    foreach ($source in $eventSources) {
        try {
            if (!(Get-EventLog -LogName Application -Source $source -ErrorAction SilentlyContinue)) {
                New-EventLog -LogName Application -Source $source
                Write-Host "Created event source: $source"
            }
        } catch {
            Write-Warning "Failed to create event source $source`: $_"
        }
    }

    # Create event logging script
    $eventLogScript = @"
param(
    [string]`$Source,
    [string]`$Message,
    [string]`$EventType = "Information",
    [int]`$EventID = 1000
)

try {
    switch (`$EventType) {
        "Error" { `$entryType = [System.Diagnostics.EventLogEntryType]::Error }
        "Warning" { `$entryType = [System.Diagnostics.EventLogEntryType]::Warning }
        "Information" { `$entryType = [System.Diagnostics.EventLogEntryType]::Information }
        default { `$entryType = [System.Diagnostics.EventLogEntryType]::Information }
    }

    Write-EventLog -LogName Application -Source `$Source -EntryType `$entryType -EventId `$EventID -Message `$Message
} catch {
    Write-Error "Failed to write to event log: `$_"
}
"@

    $scriptPath = "$BaseLogPath\write-event-log.ps1"
    $eventLogScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Windows Event Log setup completed."
    Write-Host "Event logging script: $scriptPath"
}

# Function to set up Prometheus configuration
function Set-PrometheusConfig {
    param([string]$ConfigPath)

    Write-Host "Setting up Prometheus configuration..." -ForegroundColor Green

    $prometheusConfig = @"
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']

  - job_name: 'localai-services'
    static_configs:
      - targets:
        - 'localhost:5678'  # n8n
        - 'localhost:3000'  # Open WebUI
        - 'localhost:3001'  # Flowise
        - 'localhost:6333'  # Qdrant
        - 'localhost:7474'  # Neo4j
        - 'localhost:54321' # Supabase
    scrape_interval: 30s
    metrics_path: /metrics

  - job_name: 'windows-exporter'
    static_configs:
      - targets: ['localhost:9182']
"@

    $prometheusConfig | Out-File -FilePath $ConfigPath -Encoding UTF8
    Write-Host "Prometheus configuration created: $ConfigPath"
}

# Function to set up Grafana configuration
function Set-GrafanaConfig {
    param([string]$ConfigPath)

    Write-Host "Setting up Grafana configuration..." -ForegroundColor Green

    $grafanaConfig = @"
[server]
http_port = 3000
domain = localhost

[security]
admin_user = admin
admin_password = admin

[users]
allow_sign_up = false

[auth.anonymous]
enabled = true
org_role = Viewer

[log]
level = info

[[datasources]]
name = Prometheus
type = prometheus
access = proxy
url = http://localhost:9090
isDefault = true

[[dashboards.providers]]
name = default
type = file
disableDeletion = false
updateIntervalSeconds = 10
allowUiUpdates = true
options.path = /var/lib/grafana/dashboards
"@

    $grafanaConfig | Out-File -FilePath $ConfigPath -Encoding UTF8
    Write-Host "Grafana configuration created: $ConfigPath"
}

# Function to create Grafana + Prometheus setup scripts
function New-GrafanaPrometheusSetup {
    Write-Host "Creating Grafana + Prometheus setup scripts..." -ForegroundColor Green

    # Create docker-compose for monitoring stack
    $dockerCompose = @"
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3002:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana.ini:/etc/grafana/grafana.ini
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

volumes:
  prometheus_data:
  grafana_data:
"@

    $composePath = "$BaseLogPath\docker-compose-monitoring.yml"
    $dockerCompose | Out-File -FilePath $composePath -Encoding UTF8

    Write-Host "Grafana + Prometheus docker-compose created: $composePath"
}

# Function to set up ELK stack configuration
function Set-ELKConfiguration {
    Write-Host "Setting up ELK stack configuration..." -ForegroundColor Green

    # Create Elasticsearch configuration
    $elasticConfig = @"
cluster.name: localai-cluster
node.name: localai-node-1
path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
xpack.monitoring.enabled: false
xpack.graph.enabled: false
xpack.watcher.enabled: false
xpack.ml.enabled: false
"@

    $elasticPath = "$BaseLogPath\elasticsearch.yml"
    $elasticConfig | Out-File -FilePath $elasticPath -Encoding UTF8

    # Create Logstash configuration
    $logstashConfig = @"
input {
  file {
    path => "/var/log/localai/**/*.log"
    start_position => "beginning"
    sincedb_path => "/dev/null"
  }
}

filter {
  grok {
    match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} \[%{LOGLEVEL:level}\] %{DATA:source}: %{GREEDYDATA:message}" }
  }
  date {
    match => [ "timestamp", "ISO8601" ]
  }
}

output {
  elasticsearch {
    hosts => ["localhost:9200"]
    index => "localai-logs-%{+YYYY.MM.dd}"
  }
  stdout { codec => rubydebug }
}
"@

    $logstashPath = "$BaseLogPath\logstash.conf"
    $logstashConfig | Out-File -FilePath $logstashPath -Encoding UTF8

    # Create Kibana configuration
    $kibanaConfig = @"
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://localhost:9200"]
"@

    $kibanaPath = "$BaseLogPath\kibana.yml"
    $kibanaConfig | Out-File -FilePath $kibanaPath -Encoding UTF8

    Write-Host "ELK stack configurations created."
}

# Function to create ELK stack docker-compose
function New-ELKStackCompose {
    Write-Host "Creating ELK stack docker-compose..." -ForegroundColor Green

    $elkCompose = @"
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.5.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
      - ./monitoring/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - elk

  logstash:
    image: docker.elastic.co/logstash/logstash:8.5.0
    container_name: logstash
    volumes:
      - ./monitoring/logstash.conf:/usr/share/logstash/pipeline/logstash.conf
      - /var/log/localai:/var/log/localai:ro
    ports:
      - "5044:5044"
    depends_on:
      - elasticsearch
    networks:
      - elk

  kibana:
    image: docker.elastic.co/kibana/kibana:8.5.0
    container_name: kibana
    volumes:
      - ./monitoring/kibana.yml:/usr/share/kibana/config/kibana.yml
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    networks:
      - elk

volumes:
  elasticsearch_data:

networks:
  elk:
    driver: bridge
"@

    $composePath = "$BaseLogPath\docker-compose-elk.yml"
    $elkCompose | Out-File -FilePath $composePath -Encoding UTF8

    Write-Host "ELK stack docker-compose created: $composePath"
}

# Function to create automated alerting system
function New-AutomatedAlertingSystem {
    param([string]$LogPath)

    Write-Host "Creating automated alerting system..." -ForegroundColor Green

    $alertingScript = @"
param(
    [string]`$LogPath = "$LogPath",
    [string[]]`$EmailRecipients = @("admin@yourdomain.com"),
    [string]`$SmtpServer = "smtp.gmail.com",
    [int]`$SmtpPort = 587
)

# Check for recent alerts
`$alertFiles = Get-ChildItem -Path "`$LogPath\alerts" -Filter "*.log" -File
`$recentAlerts = @()

foreach (`$file in `$alertFiles) {
    `$content = Get-Content `$file | Select-Object -Last 10
    `$recentAlerts += `$content
}

if (`$recentAlerts.Count -gt 0) {
    `$body = "Recent LocalAI System Alerts:`n`n" + (`$recentAlerts -join "`n")

    try {
        `$smtpClient = New-Object System.Net.Mail.SmtpClient(`$SmtpServer, `$SmtpPort)
        `$smtpClient.EnableSsl = `$true
        `$smtpClient.Credentials = New-Object System.Net.NetworkCredential("your-email@gmail.com", "your-app-password")

        `$mailMessage = New-Object System.Net.Mail.MailMessage
        `$mailMessage.From = "alerts@yourdomain.com"
        `$mailMessage.Subject = "LocalAI System Alerts - " + (Get-Date -Format "yyyy-MM-dd HH:mm")
        `$mailMessage.Body = `$body

        foreach (`$recipient in `$EmailRecipients) {
            `$mailMessage.To.Add(`$recipient)
        }

        `$smtpClient.Send(`$mailMessage)
        Write-Host "Alert email sent successfully."
    } catch {
        Write-Error "Failed to send alert email: `$_"
    }
}
"@

    $scriptPath = "$LogPath\automated-alerts.ps1"
    $alertingScript | Out-File -FilePath $scriptPath -Encoding UTF8

    Write-Host "Automated alerting system created: $scriptPath"
}

# Main execution
if ($SetupUptimeRobot) {
    Set-UptimeRobotMonitoring -Domain $Domain -Subdomains $Subdomains
}

if ($SetupWindowsEventLogs) {
    Set-WindowsEventLogs
}

if ($SetupGrafanaPrometheus) {
    # Create monitoring directory
    $monitoringPath = "$BaseLogPath\monitoring"
    if (!(Test-Path $monitoringPath)) {
        New-Item -ItemType Directory -Path $monitoringPath -Force
    }

    Set-PrometheusConfig -ConfigPath "$monitoringPath\prometheus.yml"
    Set-GrafanaConfig -ConfigPath "$monitoringPath\grafana.ini"
    New-GrafanaPrometheusSetup
}

if ($SetupELK) {
    # Create monitoring directory if not exists
    $monitoringPath = "$BaseLogPath\monitoring"
    if (!(Test-Path $monitoringPath)) {
        New-Item -ItemType Directory -Path $monitoringPath -Force
    }

    Set-ELKConfiguration
    New-ELKStackCompose
}

New-AutomatedAlertingSystem -LogPath $BaseLogPath

Write-Host "External monitoring services setup completed." -ForegroundColor Green
Write-Host "Configuration files saved to: $BaseLogPath"