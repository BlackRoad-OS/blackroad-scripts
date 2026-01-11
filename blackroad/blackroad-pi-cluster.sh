#!/bin/bash
# BlackRoad Pi Cluster Manager
# Coordinates: octavia (192.168.4.74), aria (192.168.4.64), shellfish

PI_NODES=(
  "pi@192.168.4.74:octavia:aarch64"
  "pi@192.168.4.64:aria:aarch64"
  "shellfish:shellfish:x86_64"
)

# Colors
RED='#FF0066'
ORANGE='#FF6B00'
YELLOW='#FF9D00'
GREEN='#00FF00'
BLUE='#0066FF'
PURPLE='#7700FF'

cluster_status() {
  echo "🖤🛣️ BlackRoad Pi Cluster Status"
  echo "================================"

  for node in "${PI_NODES[@]}"; do
    IFS=':' read -r host name arch <<< "$node"
    echo -n "[$name] ($arch): "

    if ssh -o ConnectTimeout=2 $host "uptime" 2>/dev/null; then
      echo "✅ ONLINE"
    else
      echo "❌ OFFLINE"
    fi
  done
}

cluster_benchmark() {
  echo "🖤🛣️ Running Cluster Benchmarks"
  echo "================================"

  for node in "${PI_NODES[@]}"; do
    IFS=':' read -r host name arch <<< "$node"
    echo ""
    echo "[$name] CPU Benchmark:"
    ssh $host "sysbench cpu --threads=4 --time=5 run 2>&1 | grep 'events per second'" 2>/dev/null || echo "sysbench not installed"
  done
}

cluster_install_tools() {
  echo "🖤🛣️ Installing Tools on All Nodes"
  echo "================================"

  for node in "${PI_NODES[@]}"; do
    IFS=':' read -r host name arch <<< "$node"
    echo ""
    echo "[$name] Installing performance tools..."

    if [[ "$arch" == "aarch64" ]]; then
      ssh $host "sudo apt update && sudo apt install -y sysbench stress-ng htop glances python3-pip" 2>&1 | tail -5
    else
      ssh $host "which sysbench || echo 'Install sysbench on x86_64 manually'"
    fi
  done
}

cluster_optimize() {
  echo "🖤🛣️ Optimizing All ARM Nodes"
  echo "================================"

  for node in "${PI_NODES[@]}"; do
    IFS=':' read -r host name arch <<< "$node"

    if [[ "$arch" == "aarch64" ]]; then
      echo ""
      echo "[$name] Applying optimizations..."
      ssh $host "echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null"
      ssh $host "echo 0 | sudo tee /proc/sys/vm/swappiness"
      echo "✅ Optimized"
    fi
  done
}

cluster_monitor() {
  echo "🖤🛣️ Real-time Cluster Monitor"
  echo "================================"

  while true; do
    clear
    echo "🖤🛣️ BlackRoad Pi Cluster - $(date)"
    echo "================================"

    for node in "${PI_NODES[@]}"; do
      IFS=':' read -r host name arch <<< "$node"
      echo ""
      echo "[$name] ($host):"
      ssh -o ConnectTimeout=1 $host "uptime && vcgencmd measure_temp 2>/dev/null || sensors 2>/dev/null | grep temp || echo 'temp: N/A'" 2>/dev/null || echo "OFFLINE"
    done

    sleep 5
  done
}

# Main menu
case "$1" in
  status)
    cluster_status
    ;;
  benchmark)
    cluster_benchmark
    ;;
  install)
    cluster_install_tools
    ;;
  optimize)
    cluster_optimize
    ;;
  monitor)
    cluster_monitor
    ;;
  *)
    echo "BlackRoad Pi Cluster Manager"
    echo ""
    echo "Usage: $0 {status|benchmark|install|optimize|monitor}"
    echo ""
    echo "  status    - Show cluster status"
    echo "  benchmark - Run benchmarks on all nodes"
    echo "  install   - Install tools on all nodes"
    echo "  optimize  - Optimize performance on ARM nodes"
    echo "  monitor   - Real-time monitoring"
    ;;
esac
