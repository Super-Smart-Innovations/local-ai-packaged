# Phase 7: Resource Allocation Optimization Scripts
# This script analyzes and optimizes resource allocation across all services based on 128GB host

Write-Host "Creating resource allocation optimization scripts..." -ForegroundColor Green

# Create resource monitoring and analysis script
@"
#!/bin/bash
# Resource Allocation Analysis Script
# Analyzes current resource usage and provides optimization recommendations

echo "Resource Allocation Analysis for 128GB Host"
echo "==========================================="

TOTAL_MEMORY_GB=128
RESERVED_MEMORY_GB=16  # Reserve 16GB for host OS and buffers
AVAILABLE_MEMORY_GB=`$((TOTAL_MEMORY_GB - RESERVED_MEMORY_GB))`

TOTAL_CPU_CORES=12
RESERVED_CPU_CORES=2  # Reserve 2 cores for host OS
AVAILABLE_CPU_CORES=`$((TOTAL_CPU_CORES - RESERVED_CPU_CORES))`

echo "Host Resources:"
echo "- Total Memory: `${TOTAL_MEMORY_GB}GB"
echo "- Available Memory: `${AVAILABLE_MEMORY_GB}GB (after `${RESERVED_MEMORY_GB}GB reservation)"
echo "- Total CPU Cores: `${TOTAL_CPU_CORES}"
echo "- Available CPU Cores: `${AVAILABLE_CPU_CORES} (after `${RESERVED_CPU_CORES} core reservation)"
echo ""

# Get current Docker resource usage
echo "Current Docker Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo ""
echo "Recommended Resource Allocation:"
echo "==============================="

# Calculate optimal allocations
OLLAMA_MEMORY_GB=`$((AVAILABLE_MEMORY_GB * 30 / 100))`  # 30% for Ollama
N8N_MEMORY_GB=`$((AVAILABLE_MEMORY_GB * 20 / 100))`     # 20% for N8N
SUPABASE_MEMORY_GB=`$((AVAILABLE_MEMORY_GB * 15 / 100))` # 15% for Supabase
OPENWEBUI_MEMORY_GB=`$((AVAILABLE_MEMORY_GB * 10 / 100))` # 10% for OpenWebUI
OTHER_MEMORY_GB=`$((AVAILABLE_MEMORY_GB * 25 / 100))`   # 25% for other services

echo "Memory Allocation (GB):"
echo "- Ollama: `${OLLAMA_MEMORY_GB}GB"
echo "- N8N: `${N8N_MEMORY_GB}GB"
echo "- Supabase/PostgreSQL: `${SUPABASE_MEMORY_GB}GB"
echo "- OpenWebUI: `${OPENWEBUI_MEMORY_GB}GB"
echo "- Other services: `${OTHER_MEMORY_GB}GB"
echo ""

OLLAMA_CPU=`$((AVAILABLE_CPU_CORES * 40 / 100))`  # 40% for Ollama
N8N_CPU=`$((AVAILABLE_CPU_CORES * 25 / 100))`     # 25% for N8N
SUPABASE_CPU=`$((AVAILABLE_CPU_CORES * 20 / 100))` # 20% for Supabase
OTHER_CPU=`$((AVAILABLE_CPU_CORES * 15 / 100))`   # 15% for other services

echo "CPU Allocation (cores):"
echo "- Ollama: `${OLLAMA_CPU}"
echo "- N8N: `${N8N_CPU}"
echo "- Supabase/PostgreSQL: `${SUPABASE_CPU}"
echo "- Other services: `${OTHER_CPU}"
echo ""

echo "Optimization Recommendations:"
echo "1. Monitor memory usage with 'docker stats'"
echo "2. Adjust limits based on actual usage patterns"
echo "3. Consider GPU memory for Ollama workloads"
echo "4. Use resource reservations to ensure minimum allocations"
echo "5. Implement horizontal scaling for high-traffic services"
"@ | Out-File -FilePath "resource-analysis.sh" -Encoding UTF8

# Create automated resource scaling script
@"
#!/bin/bash
# Automated Resource Scaling Script
# Adjusts resource limits based on current usage and performance metrics

LOG_FILE="resource-scaling.log"
THRESHOLD_MEMORY=80  # Scale up if memory usage > 80%
THRESHOLD_CPU=70     # Scale up if CPU usage > 70%

log() {
    echo "[`$(date +'%Y-%m-%d %H:%M:%S')`] `$1`" >> "`$LOG_FILE`"
}

get_container_memory_usage() {
    docker stats --no-stream --format "{{.Name}}:{{.MemPerc}}" | grep "^`$1`:" | cut -d':' -f2 | sed 's/%//'
}

get_container_cpu_usage() {
    docker stats --no-stream --format "{{.Name}}:{{.CPUPerc}}" | grep "^`$1`:" | cut -d':' -f2 | sed 's/%//'
}

scale_service() {
    SERVICE_NAME=`$1`
    CURRENT_MEMORY=`$(get_container_memory_usage `$SERVICE_NAME`)`
    CURRENT_CPU=`$(get_container_cpu_usage `$SERVICE_NAME`)`

    if (( `$(echo "`$CURRENT_MEMORY` > `$THRESHOLD_MEMORY`" | bc -l)` )); then
        log "High memory usage detected for `$SERVICE_NAME`: `$CURRENT_MEMORY`%"
        # Increase memory limit by 25%
        docker update --memory +256m `$SERVICE_NAME` 2>/dev/null || log "Failed to scale memory for `$SERVICE_NAME`"
    fi

    if (( `$(echo "`$CURRENT_CPU` > `$THRESHOLD_CPU`" | bc -l)` )); then
        log "High CPU usage detected for `$SERVICE_NAME`: `$CURRENT_CPU`%"
        # Increase CPU limit by 0.5 cores
        docker update --cpus +0.5 `$SERVICE_NAME` 2>/dev/null || log "Failed to scale CPU for `$SERVICE_NAME`"
    fi
}

log "Starting automated resource scaling check"

# Check and scale critical services
SERVICES=("ollama" "n8n" "postgres" "open-webui")

for service in "`${SERVICES[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^`$service`$"; then
        scale_service `$service`
    else
        log "Service `$service` not running, skipping scaling check"
    fi
done

log "Resource scaling check completed"
"@ | Out-File -FilePath "auto-resource-scaling.sh" -Encoding UTF8

# Create resource limits validation script
@"
#!/bin/bash
# Resource Limits Validation Script
# Validates that resource limits are properly configured and within safe bounds

echo "Validating Resource Limits Configuration"
echo "========================================"

# Define maximum safe limits (80% of host resources)
MAX_MEMORY_GB=`$((128 * 80 / 100))`  # 102GB
MAX_CPU_CORES=`$((12 * 80 / 100))`   # 9.6 cores

echo "Safe limits for this host:"
echo "- Maximum Memory: `${MAX_MEMORY_GB}GB (80% of 128GB)"
echo "- Maximum CPU: `${MAX_CPU_CORES} cores (80% of 12 cores)"
echo ""

ISSUES_FOUND=0

# Check docker-compose.yml resource limits
if [ -f "docker-compose.yml" ]; then
    echo "Checking docker-compose.yml resource limits..."

    # Check for services without resource limits
    UNLIMITED_SERVICES=`$(grep -A 10 "^  [a-zA-Z].*:" docker-compose.yml | grep -B 10 -A 20 "image:" | grep "^  [a-zA-Z].*:" | xargs)`

    for service in `$UNLIMITED_SERVICES`; do
        if ! grep -A 20 "^  `$service`:" docker-compose.yml | grep -q "deploy:"; then
            echo "WARNING: Service '$service' has no resource limits configured"
            ISSUES_FOUND=`$((ISSUES_FOUND + 1))`
        fi
    done

    # Check for excessive memory limits
    MEMORY_LIMITS=`$(grep -A 10 "memory:" docker-compose.yml | grep "memory:" | grep -o "[0-9]*G" | sed 's/G//')`

    for mem in `$MEMORY_LIMITS`; do
        if [ "`$mem`" -gt "`$MAX_MEMORY_GB`" ]; then
            echo "ERROR: Memory limit `${mem}GB exceeds safe limit `${MAX_MEMORY_GB}GB"
            ISSUES_FOUND=`$((ISSUES_FOUND + 1))`
        fi
    done

    # Check for excessive CPU limits
    CPU_LIMITS=`$(grep -A 10 "cpus:" docker-compose.yml | grep "cpus:" | grep -o "cpus: '[0-9]*\.*[0-9]*'" | grep -o "[0-9]*\.*[0-9]*")`

    for cpu in `$CPU_LIMITS`; do
        if (( `$(echo "`$cpu` > `$MAX_CPU_CORES`" | bc -l)` )); then
            echo "ERROR: CPU limit `${cpu} exceeds safe limit `${MAX_CPU_CORES}"
            ISSUES_FOUND=`$((ISSUES_FOUND + 1))`
        fi
    done
else
    echo "ERROR: docker-compose.yml not found"
    ISSUES_FOUND=`$((ISSUES_FOUND + 1))`
fi

echo ""
if [ "`$ISSUES_FOUND`" -eq 0 ]; then
    echo "✓ All resource limits are properly configured"
else
    echo "✗ Found `${ISSUES_FOUND}` resource limit issues that need attention"
    echo ""
    echo "Recommendations:"
    echo "1. Add resource limits to services without them"
    echo "2. Ensure memory limits don't exceed `${MAX_MEMORY_GB}GB"
    echo "3. Ensure CPU limits don't exceed `${MAX_CPU_CORES} cores"
    echo "4. Use reservations to guarantee minimum resources"
fi
"@ | Out-File -FilePath "validate-resource-limits.sh" -Encoding UTF8

# Create performance benchmarking script
@"
#!/bin/bash
# Performance Benchmarking Script
# Runs performance tests and generates optimization recommendations

echo "Performance Benchmarking Suite"
echo "==============================="

RESULTS_DIR="benchmark-results"
mkdir -p `$RESULTS_DIR`

TIMESTAMP=`$(date +'%Y%m%d_%H%M%S')`
RESULT_FILE="`$RESULTS_DIR`/benchmark_`$TIMESTAMP`.txt"

echo "Benchmark Results - `$TIMESTAMP`" > `$RESULT_FILE`
echo "=================================" >> `$RESULT_FILE`

# Docker performance test
echo "Running Docker performance tests..."
echo "Docker Performance:" >> `$RESULT_FILE`
docker version >> `$RESULT_FILE` 2>&1
echo "" >> `$RESULT_FILE`

# Memory bandwidth test (if available)
if command -v sysbench &> /dev/null; then
    echo "Memory Performance:" >> `$RESULT_FILE`
    sysbench memory --memory-block-size=1K --memory-total-size=100G --memory-access-mode=rnd run >> `$RESULT_FILE` 2>&1
    echo "" >> `$RESULT_FILE`
fi

# Disk I/O performance test
echo "Disk I/O Performance:" >> `$RESULT_FILE`
dd if=/dev/zero of=/tmp/testfile bs=1M count=1000 conv=fdatasync 2>&1 | tail -1 >> `$RESULT_FILE`
rm -f /tmp/testfile
echo "" >> `$RESULT_FILE`

# Network performance test (if curl available)
if command -v curl &> /dev/null; then
    echo "Network Performance:" >> `$RESULT_FILE`
    curl -w "@curl-format.txt" -o /dev/null -s http://httpbin.org/get >> `$RESULT_FILE` 2>/dev/null || echo "Network test failed" >> `$RESULT_FILE`
    echo "" >> `$RESULT_FILE`
fi

# Container startup time test
echo "Container Startup Performance:" >> `$RESULT_FILE`
START_TIME=`$(date +%s%N)`
docker run --rm hello-world > /dev/null 2>&1
END_TIME=`$(date +%s%N)`
STARTUP_TIME=`$(echo "scale=2; (`$END_TIME` - `$START_TIME`) / 1000000" | bc)`
echo "Container startup time: `$STARTUP_TIME` ms" >> `$RESULT_FILE`
echo "" >> `$RESULT_FILE`

# Generate recommendations
echo "Performance Recommendations:" >> `$RESULT_FILE`
echo "1. If disk I/O is slow (< 500 MB/s), consider using SSD storage" >> `$RESULT_FILE`
echo "2. If memory bandwidth is low (< 10 GB/s), check RAM configuration" >> `$RESULT_FILE`
echo "3. If container startup > 500ms, optimize Docker storage driver" >> `$RESULT_FILE`
echo "4. Monitor network latency for API performance" >> `$RESULT_FILE`

echo "Benchmark completed. Results saved to: `$RESULT_FILE`"
echo "Review recommendations in the results file."
"@ | Out-File -FilePath "performance-benchmark.sh" -Encoding UTF8

# Create curl format file for network testing
@"
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
"@ | Out-File -FilePath "curl-format.txt" -Encoding UTF8

Write-Host "Resource allocation optimization scripts created." -ForegroundColor Green
Write-Host ""
Write-Host "Scripts created:" -ForegroundColor Cyan
Write-Host "- resource-analysis.sh: Analyzes current resource usage and provides recommendations"
Write-Host "- auto-resource-scaling.sh: Automatically adjusts resource limits based on usage"
Write-Host "- validate-resource-limits.sh: Validates resource configuration safety"
Write-Host "- performance-benchmark.sh: Runs comprehensive performance tests"
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "1. Run './resource-analysis.sh' to analyze current allocation"
Write-Host "2. Run './validate-resource-limits.sh' to check configuration safety"
Write-Host "3. Run './performance-benchmark.sh' for performance testing"
Write-Host "4. Schedule './auto-resource-scaling.sh' for automated adjustments"