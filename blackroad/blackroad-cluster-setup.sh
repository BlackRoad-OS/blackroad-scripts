#!/bin/bash
# BlackRoad Cluster Setup
# Creates distributed computing cluster across Pi fleet + Mac

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🖤 BLACKROAD CLUSTER SETUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cluster configuration
PRIMARY="octavia"
WORKERS="lucidia aria alice"
CLUSTER_NAME="blackroad-quantum-cluster"

# Step 1: Initialize Docker Swarm on primary
echo ""
echo "Step 1: Initializing Docker Swarm on $PRIMARY..."
ssh $PRIMARY << 'EOF'
# Check if already in swarm
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "⚠️  Already in swarm mode, leaving first..."
    docker swarm leave --force 2>/dev/null || true
fi

# Initialize swarm on WiFi IP (for now, will move to carrier later)
SWARM_IP=$(ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "Initializing swarm on $SWARM_IP..."
docker swarm init --advertise-addr $SWARM_IP

# Get join token for workers
docker swarm join-token worker -q > /tmp/swarm-token
echo "✅ Swarm initialized on $SWARM_IP"
EOF

# Get join token and manager IP
JOIN_TOKEN=$(ssh $PRIMARY "cat /tmp/swarm-token")
MANAGER_IP=$(ssh $PRIMARY "docker swarm join-token worker | grep 'docker swarm join' | awk '{print \$6}' | cut -d: -f1")

echo "Join token: ${JOIN_TOKEN:0:20}..."
echo "Manager IP: $MANAGER_IP"

# Step 2: Join worker nodes
echo ""
echo "Step 2: Joining worker nodes to swarm..."
for host in $WORKERS; do
    echo "  Joining $host..."
    ssh $host << EOF
# Leave any existing swarm
docker swarm leave --force 2>/dev/null || true

# Join the swarm
docker swarm join --token $JOIN_TOKEN $MANAGER_IP:2377

echo "✅ $host joined swarm"
EOF
done

# Step 3: Verify cluster
echo ""
echo "Step 3: Verifying cluster..."
ssh $PRIMARY "docker node ls"

# Step 4: Label nodes for workload placement
echo ""
echo "Step 4: Labeling nodes..."
ssh $PRIMARY << 'EOF'
# Label nodes based on capabilities
docker node update --label-add role=primary --label-add hailo=true octavia 2>/dev/null || true
docker node update --label-add role=brain --label-add cpu=high lucidia 2>/dev/null || true
docker node update --label-add role=worker aria 2>/dev/null || true
docker node update --label-add role=gateway alice 2>/dev/null || true

echo "✅ Nodes labeled"
docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.Availability}}"
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ BlackRoad Cluster Initialized!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Cluster Status:"
ssh $PRIMARY "docker node ls"
echo ""
echo "Next steps:"
echo "  1. Deploy NATS: ./blackroad-deploy-nats.sh"
echo "  2. Deploy Quantum Workers: ./blackroad-deploy-quantum.sh"
echo "  3. Deploy Monitoring: ./blackroad-deploy-monitoring.sh"
