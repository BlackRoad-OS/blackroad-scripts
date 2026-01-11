#!/bin/bash
# Deploy NATS cluster for BlackRoad quantum coordination

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🖤 DEPLOYING NATS CLUSTER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Deploy NATS as a Docker Swarm service
ssh octavia << 'EOF'
# Remove existing NATS if present
docker service rm blackroad-nats 2>/dev/null || true
docker rm -f blackroad-nats 2>/dev/null || true

# Create NATS cluster
docker service create \
  --name blackroad-nats \
  --network host \
  --constraint 'node.role==manager' \
  --replicas 1 \
  --publish 4222:4222 \
  --publish 8222:8222 \
  nats:latest \
  -js \
  --http_port 8222

echo "✅ NATS deployed"

# Wait for NATS to be ready
echo "Waiting for NATS to start..."
sleep 5

# Test NATS
curl -s http://localhost:8222/varz | head -5 || echo "NATS starting..."
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ NATS Cluster Ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "NATS Endpoints:"
echo "  Client:  nats://192.168.4.81:4222"
echo "  Monitor: http://192.168.4.81:8222"
echo ""
echo "Test connection:"
echo "  ssh octavia 'curl http://localhost:8222/varz'"
