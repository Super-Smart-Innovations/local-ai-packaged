#!/bin/bash

# Phase 5: System Resource Monitoring Inside Ubuntu Container
# This script provides comprehensive monitoring tools for the Ubuntu container

set -e

LOG_DIR="/var/log/localai/monitoring"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to monitor system resources with htop-like output
monitor_system_resources() {
    echo "=== System Resource Monitoring ($TIMESTAMP) ===" | tee -a "$LOG_DIR/system-resources.log"

    echo "CPU and Memory Usage:" | tee -a "$LOG_DIR/system-resources.log"
    top -b -n1 | head -20 | tee -a "$LOG_DIR/system-resources.log"

    echo -e "\nMemory Details:" | tee -a "$LOG_DIR/system-resources.log"
    free -h | tee -a "$LOG_DIR/system-resources.log"

    echo -e "\nDisk Usage:" | tee -a "$LOG_DIR/system-resources.log"
    df -h | tee -a "$LOG_DIR/system-resources.log"

    echo -e "\nNetwork Statistics:" | tee -a "$LOG_DIR/system-resources.log"
    ip -s link | tee -a "$LOG_DIR/system-resources.log"
}

# Function to monitor I/O operations with iotop-like functionality
monitor_io_operations() {
    echo "=== I/O Operations Monitoring ($TIMESTAMP) ===" | tee -a "$LOG_DIR/io-operations.log"

    echo "Disk I/O Statistics:" | tee -a "$LOG_DIR/io-operations.log"
    iostat -x 1 5 2>/dev/null || echo "iostat not available, using alternative method" | tee -a "$LOG_DIR/io-operations.log"
    iotop -b -n 1 2>/dev/null || echo "iotop not available" | tee -a "$LOG_DIR/io-operations.log"

    echo -e "\nProcess I/O:" | tee -a "$LOG_DIR/io-operations.log"
    ps aux --sort=-pcpu | head -10 | tee -a "$LOG_DIR/io-operations.log"
}

# Function to monitor disk usage with ncdu-like output
monitor_disk_usage() {
    echo "=== Disk Usage Analysis ($TIMESTAMP) ===" | tee -a "$LOG_DIR/disk-usage.log"

    echo "Largest directories:" | tee -a "$LOG_DIR/disk-usage.log"
    du -sh /* 2>/dev/null | sort -hr | head -10 | tee -a "$LOG_DIR/disk-usage.log"

    echo -e "\nDetailed disk usage:" | tee -a "$LOG_DIR/disk-usage.log"
    ncdu -x / --exclude /proc --exclude /sys --exclude /dev 2>/dev/null || du -ah / | sort -hr | head -20 | tee -a "$LOG_DIR/disk-usage.log"
}

# Function to monitor Docker containers from within the container
monitor_nested_containers() {
    echo "=== Nested Container Monitoring ($TIMESTAMP) ===" | tee -a "$LOG_DIR/nested-containers.log"

    if command -v docker &> /dev/null; then
        echo "Docker containers:" | tee -a "$LOG_DIR/nested-containers.log"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | tee -a "$LOG_DIR/nested-containers.log"

        echo -e "\nContainer stats:" | tee -a "$LOG_DIR/nested-containers.log"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | tee -a "$LOG_DIR/nested-containers.log"
    else
        echo "Docker not available in this container" | tee -a "$LOG_DIR/nested-containers.log"
    fi
}

# Function to monitor running processes
monitor_processes() {
    echo "=== Process Monitoring ($TIMESTAMP) ===" | tee -a "$LOG_DIR/processes.log"

    echo "Top CPU processes:" | tee -a "$LOG_DIR/processes.log"
    ps aux --sort=-%cpu | head -10 | tee -a "$LOG_DIR/processes.log"

    echo -e "\nTop memory processes:" | tee -a "$LOG_DIR/processes.log"
    ps aux --sort=-%mem | head -10 | tee -a "$LOG_DIR/processes.log"

    echo -e "\nZombie processes:" | tee -a "$LOG_DIR/processes.log"
    ps aux | awk '{print $8}' | grep -c "Z" | xargs echo "Zombie processes found:" | tee -a "$LOG_DIR/processes.log"
}

# Function to check system health
check_system_health() {
    echo "=== System Health Check ($TIMESTAMP) ===" | tee -a "$LOG_DIR/health-check.log"

    echo "System uptime:" | tee -a "$LOG_DIR/health-check.log"
    uptime | tee -a "$LOG_DIR/health-check.log"

    echo -e "\nLoad average:" | tee -a "$LOG_DIR/health-check.log"
    cat /proc/loadavg | tee -a "$LOG_DIR/health-check.log"

    echo -e "\nSystem information:" | tee -a "$LOG_DIR/health-check.log"
    uname -a | tee -a "$LOG_DIR/health-check.log"

    echo -e "\nAvailable entropy:" | tee -a "$LOG_DIR/health-check.log"
    cat /proc/sys/kernel/random/entropy_avail | tee -a "$LOG_DIR/health-check.log"
}

# Install monitoring tools if not present
install_monitoring_tools() {
    echo "Checking and installing monitoring tools..."

    # Update package list
    apt-get update -qq

    # Install htop if not present
    if ! command -v htop &> /dev/null; then
        apt-get install -y htop
    fi

    # Install iotop if not present
    if ! command -v iotop &> /dev/null; then
        apt-get install -y iotop
    fi

    # Install ncdu if not present
    if ! command -v ncdu &> /dev/null; then
        apt-get install -y ncdu
    fi

    # Install sysstat for iostat
    if ! command -v iostat &> /dev/null; then
        apt-get install -y sysstat
    fi

    echo "Monitoring tools installation completed."
}

# Main execution
case "$1" in
    "install")
        install_monitoring_tools
        ;;
    "monitor")
        monitor_system_resources
        monitor_io_operations
        monitor_disk_usage
        monitor_nested_containers
        monitor_processes
        check_system_health
        ;;
    "continuous")
        echo "Starting continuous monitoring (Ctrl+C to stop)..."
        while true; do
            monitor_system_resources
            monitor_nested_containers
            monitor_processes
            sleep 300  # Monitor every 5 minutes
        done
        ;;
    *)
        echo "Usage: $0 {install|monitor|continuous}"
        echo "  install    - Install monitoring tools"
        echo "  monitor    - Run single monitoring cycle"
        echo "  continuous - Run continuous monitoring"
        exit 1
        ;;
esac

echo "Container monitoring completed. Logs saved to $LOG_DIR"