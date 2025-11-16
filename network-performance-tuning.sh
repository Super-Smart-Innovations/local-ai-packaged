#!/bin/bash
# Network Performance Tuning Script for Docker and System

echo "Optimizing network performance settings..."

# System-level network optimizations
echo "Applying system-level network optimizations..."

# Increase network buffer sizes
sudo sysctl -w net.core.rmem_max=26214400 2>/dev/null || echo "Cannot set rmem_max (requires root)"
sudo sysctl -w net.core.wmem_max=26214400 2>/dev/null || echo "Cannot set wmem_max (requires root)"
sudo sysctl -w net.core.rmem_default=26214400 2>/dev/null || echo "Cannot set rmem_default (requires root)"
sudo sysctl -w net.core.wmem_default=26214400 2>/dev/null || echo "Cannot set wmem_default (requires root)"

# TCP optimizations
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 26214400" 2>/dev/null || echo "Cannot set tcp_rmem"
sudo sysctl -w net.ipv4.tcp_wmem="4096 16384 26214400" 2>/dev/null || echo "Cannot set tcp_wmem"
sudo sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null || echo "Cannot set congestion control (BBR not available)"

# Enable TCP fast open
sudo sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null || echo "Cannot enable TCP fast open"

# Optimize connection tracking
sudo sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=86400 2>/dev/null || echo "Cannot set conntrack timeout"

# Docker-specific network optimizations
echo "Applying Docker network optimizations..."

# Create optimized networks if they don't exist
docker network ls | grep -q "localai-network" || docker network create --driver bridge \
  --opt "com.docker.network.bridge.name=localai-br0" \
  --opt "com.docker.network.bridge.enable_ip_forward=true" \
  --opt "com.docker.network.bridge.enable_icc=true" \
  --opt "com.docker.network.driver.mtu=1500" \
  --subnet=172.20.0.0/16 \
  localai-network

docker network ls | grep -q "database-network" || docker network create --driver bridge \
  --internal \
  --opt "com.docker.network.bridge.name=localai-db-br0" \
  --opt "com.docker.network.bridge.enable_ip_forward=false" \
  --opt "com.docker.network.bridge.enable_icc=true" \
  --opt "com.docker.network.driver.mtu=9000" \
  --subnet=172.21.0.0/16 \
  database-network

docker network ls | grep -q "ai-network" || docker network create --driver bridge \
  --opt "com.docker.network.bridge.name=localai-ai-br0" \
  --opt "com.docker.network.bridge.enable_ip_forward=true" \
  --opt "com.docker.network.bridge.enable_icc=true" \
  --opt "com.docker.network.driver.mtu=9000" \
  --subnet=172.22.0.0/16 \
  ai-network

# Configure iptables rules for better performance (requires root)
echo "Configuring iptables optimizations..."

# Allow established connections (performance optimization)
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || echo "Cannot configure iptables (requires root)"

# Rate limiting for DoS protection
sudo iptables -A INPUT -p tcp --dport 80 -m limit --limit 100/minute --limit-burst 200 -j ACCEPT 2>/dev/null || echo "Cannot configure rate limiting"
sudo iptables -A INPUT -p tcp --dport 443 -m limit --limit 100/minute --limit-burst 200 -j ACCEPT 2>/dev/null || echo "Cannot configure rate limiting"

echo "Network performance optimizations applied."
echo ""
echo "Applied optimizations:"
echo "- Increased network buffer sizes (25MB)"
echo "- Enabled BBR congestion control"
echo "- Enabled TCP fast open"
echo "- Optimized connection tracking timeouts"
echo "- Created performance-optimized Docker networks"
echo "- Configured iptables rules for better throughput"
echo ""
echo "Note: Some optimizations require root privileges and may not apply in all environments."
