#!/bin/bash
# Resource Allocation Analysis Script
# Analyzes current resource usage and provides optimization recommendations

echo "Resource Allocation Analysis for 128GB Host"
echo "==========================================="

TOTAL_MEMORY_GB=128
RESERVED_MEMORY_GB=16  # Reserve 16GB for host OS and buffers
AVAILABLE_MEMORY_GB=$((TOTAL_MEMORY_GB - RESERVED_MEMORY_GB))

TOTAL_CPU_CORES=12
RESERVED_CPU_CORES=2  # Reserve 2 cores for host OS
AVAILABLE_CPU_CORES=$((TOTAL_CPU_CORES - RESERVED_CPU_CORES))

echo "Host Resources:"
echo "- Total Memory: ${TOTAL_MEMORY_GB}GB"
echo "- Available Memory: ${AVAILABLE_MEMORY_GB}GB (after ${RESERVED_MEMORY_GB}GB reservation)"
echo "- Total CPU Cores: ${TOTAL_CPU_CORES}"
echo "- Available CPU Cores: ${AVAILABLE_CPU_CORES} (after ${RESERVED_CPU_CORES} core reservation)"
echo ""

# Get current Docker resource usage
echo "Current Docker Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo ""
echo "Recommended Resource Allocation:"
echo "==============================="

# Calculate optimal allocations
OLLAMA_MEMORY_GB=$((AVAILABLE_MEMORY_GB * 30 / 100))  # 30% for Ollama
N8N_MEMORY_GB=$((AVAILABLE_MEMORY_GB * 20 / 100))     # 20% for N8N
SUPABASE_MEMORY_GB=$((AVAILABLE_MEMORY_GB * 15 / 100)) # 15% for Supabase
OPENWEBUI_MEMORY_GB=$((AVAILABLE_MEMORY_GB * 10 / 100)) # 10% for OpenWebUI
OTHER_MEMORY_GB=$((AVAILABLE_MEMORY_GB * 25 / 100))   # 25% for other services

echo "Memory Allocation (GB):"
echo "- Ollama: ${OLLAMA_MEMORY_GB}GB"
echo "- N8N: ${N8N_MEMORY_GB}GB"
echo "- Supabase/PostgreSQL: ${SUPABASE_MEMORY_GB}GB"
echo "- OpenWebUI: ${OPENWEBUI_MEMORY_GB}GB"
echo "- Other services: ${OTHER_MEMORY_GB}GB"
echo ""

OLLAMA_CPU=$((AVAILABLE_CPU_CORES * 40 / 100))  # 40% for Ollama
N8N_CPU=$((AVAILABLE_CPU_CORES * 25 / 100))     # 25% for N8N
SUPABASE_CPU=$((AVAILABLE_CPU_CORES * 20 / 100)) # 20% for Supabase
OTHER_CPU=$((AVAILABLE_CPU_CORES * 15 / 100))   # 15% for other services

echo "CPU Allocation (cores):"
echo "- Ollama: ${OLLAMA_CPU}"
echo "- N8N: ${N8N_CPU}"
echo "- Supabase/PostgreSQL: ${SUPABASE_CPU}"
echo "- Other services: ${OTHER_CPU}"
echo ""

echo "Optimization Recommendations:"
echo "1. Monitor memory usage with 'docker stats'"
echo "2. Adjust limits based on actual usage patterns"
echo "3. Consider GPU memory for Ollama workloads"
echo "4. Use resource reservations to ensure minimum allocations"
echo "5. Implement horizontal scaling for high-traffic services"
