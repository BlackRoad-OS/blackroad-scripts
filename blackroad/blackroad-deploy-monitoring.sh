#!/bin/bash
# Deploy Prometheus + Grafana monitoring stack for BlackRoad quantum cluster

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 DEPLOYING BLACKROAD QUANTUM MONITORING STACK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Create monitoring network if not exists
echo ""
echo "Step 1: Setting up monitoring network..."
ssh octavia "docker network ls | grep -q blackroad-monitor || docker network create --driver overlay blackroad-monitor"
echo "✅ Network ready"

# Step 2: Deploy Prometheus for metrics collection
echo ""
echo "Step 2: Deploying Prometheus..."
ssh octavia << 'EOF'
# Create Prometheus config
mkdir -p ~/monitoring
cat > ~/monitoring/prometheus.yml << 'PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Node exporter (system metrics)
  - job_name: 'node'
    static_configs:
      - targets:
        - 'octavia:9100'
        - 'lucidia:9100'
        - 'aria:9100'
        - 'alice:9100'
        labels:
          cluster: 'blackroad-quantum'

  # Quantum metrics endpoint (to be implemented)
  - job_name: 'quantum'
    static_configs:
      - targets:
        - 'octavia:9101'
        - 'lucidia:9101'
        - 'aria:9101'
        - 'alice:9101'
        labels:
          cluster: 'blackroad-quantum'

  # NATS monitoring
  - job_name: 'nats'
    static_configs:
      - targets: ['blackroad-nats:8222']
PROM

# Deploy Prometheus service
docker service create \
  --name blackroad-prometheus \
  --network blackroad-net \
  --network blackroad-monitor \
  --mount type=bind,source=$HOME/monitoring/prometheus.yml,target=/etc/prometheus/prometheus.yml \
  --publish 9090:9090 \
  --constraint 'node.role==manager' \
  prom/prometheus:latest \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --web.console.libraries=/usr/share/prometheus/console_libraries \
  --web.console.templates=/usr/share/prometheus/consoles

echo "✅ Prometheus deployed"
EOF

# Step 3: Deploy Grafana for visualization
echo ""
echo "Step 3: Deploying Grafana..."
ssh octavia << 'EOF'
docker service create \
  --name blackroad-grafana \
  --network blackroad-monitor \
  --publish 3000:3000 \
  --constraint 'node.role==manager' \
  --env GF_SECURITY_ADMIN_PASSWORD=blackroad2026 \
  --env GF_INSTALL_PLUGINS=grafana-piechart-panel \
  grafana/grafana:latest

echo "✅ Grafana deployed"
EOF

# Step 4: Deploy Node Exporters on all Pis
echo ""
echo "Step 4: Deploying Node Exporters on all nodes..."
for host in octavia lucidia aria alice; do
    echo "  Deploying to $host..."
    ssh $host << 'NODEEXP'
# Check if node_exporter already running
if pgrep -x "node_exporter" > /dev/null; then
    echo "    Node exporter already running"
else
    # Download and run node_exporter
    if [ ! -f ~/node_exporter ]; then
        curl -sL https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-arm64.tar.gz | tar xz
        mv node_exporter-*/node_exporter ~/
        chmod +x ~/node_exporter
    fi

    # Run in background
    nohup ~/node_exporter --web.listen-address=:9100 > /tmp/node_exporter.log 2>&1 &
    echo "    ✅ Node exporter started"
fi
NODEEXP
done

# Step 5: Create quantum metrics exporter
echo ""
echo "Step 5: Creating quantum metrics exporters..."
for host in octavia lucidia aria alice; do
    echo "  Setting up quantum metrics on $host..."
    ssh $host << 'QMETRICS'
cat > ~/quantum-metrics-exporter.py << 'PYMETRICS'
#!/usr/bin/env python3
"""
BlackRoad Quantum Metrics Exporter
Exposes quantum computation metrics in Prometheus format
"""

import json
import time
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

NODE_NAME = socket.gethostname()
METRICS_PORT = 9101

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            metrics = self.generate_metrics()
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; version=0.0.4')
            self.end_headers()
            self.wfile.write(metrics.encode())
        else:
            self.send_error(404)

    def generate_metrics(self):
        """Generate Prometheus metrics from quantum test results"""
        lines = []

        # Read latest quantum results
        results_file = f'/tmp/qudit-trinary-results-{NODE_NAME}.json'
        if Path(results_file).exists():
            with open(results_file) as f:
                data = json.load(f)

            # Qutrit entanglement metrics
            for test in data.get('tests', []):
                if test.get('test') == 'qutrit_entanglement':
                    lines.append(f'# HELP quantum_qutrit_entropy_bits Von Neumann entropy of qutrit entanglement')
                    lines.append(f'# TYPE quantum_qutrit_entropy_bits gauge')
                    lines.append(f'quantum_qutrit_entropy_bits{{node="{NODE_NAME}",dimension="3x3"}} {test["entropy_bits"]}')

                    lines.append(f'# HELP quantum_qutrit_time_ms Qutrit computation time in milliseconds')
                    lines.append(f'# TYPE quantum_qutrit_time_ms gauge')
                    lines.append(f'quantum_qutrit_time_ms{{node="{NODE_NAME}"}} {test["time_ms"]}')

                # High-dimensional qudit metrics
                if test.get('test') == 'high_dimensional_qudits':
                    for result in test.get('results', []):
                        dim = result['dimensions'].replace('=', '_').replace('⊗', 'x')

                        lines.append(f'# HELP quantum_hilbert_dimension Hilbert space dimension')
                        lines.append(f'# TYPE quantum_hilbert_dimension gauge')
                        lines.append(f'quantum_hilbert_dimension{{node="{NODE_NAME}",dims="{result["dimensions"]}"}} {result["hilbert_dim"]}')

                        lines.append(f'# HELP quantum_computation_time_ms Computation time in milliseconds')
                        lines.append(f'# TYPE quantum_computation_time_ms gauge')
                        lines.append(f'quantum_computation_time_ms{{node="{NODE_NAME}",dims="{result["dimensions"]}"}} {result["time_ms"]}')

                # Fibonacci golden ratio metrics
                if test.get('test') == 'fibonacci_qudits':
                    for result in test.get('results', []):
                        dims = result['dimensions']
                        accuracy = float(result['accuracy'].rstrip('%'))

                        lines.append(f'# HELP quantum_golden_ratio_accuracy_percent Golden ratio discovery accuracy')
                        lines.append(f'# TYPE quantum_golden_ratio_accuracy_percent gauge')
                        lines.append(f'quantum_golden_ratio_accuracy_percent{{node="{NODE_NAME}",dims="{dims}"}} {accuracy}')

        # Node status
        lines.append(f'# HELP quantum_node_online Node online status')
        lines.append(f'# TYPE quantum_node_online gauge')
        lines.append(f'quantum_node_online{{node="{NODE_NAME}"}} 1')

        return '\n'.join(lines) + '\n'

    def log_message(self, format, *args):
        pass  # Suppress HTTP logs

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', METRICS_PORT), MetricsHandler)
    print(f'Quantum metrics exporter running on :{METRICS_PORT}')
    server.serve_forever()
PYMETRICS

chmod +x ~/quantum-metrics-exporter.py

# Kill old exporter if running
pkill -f quantum-metrics-exporter.py || true

# Start new exporter
nohup python3 ~/quantum-metrics-exporter.py > /tmp/quantum-metrics.log 2>&1 &
echo "    ✅ Quantum metrics exporter started on :9101"
QMETRICS
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ MONITORING STACK DEPLOYED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Access Points:"
echo "  📊 Prometheus: http://192.168.4.81:9090"
echo "  📈 Grafana:    http://192.168.4.81:3000"
echo "                 (admin/blackroad2026)"
echo ""
echo "Quantum Metrics Endpoints:"
echo "  octavia: http://192.168.4.81:9101/metrics"
echo "  lucidia: http://192.168.4.38:9101/metrics"
echo "  aria:    http://192.168.4.82:9101/metrics"
echo "  alice:   http://192.168.4.49:9101/metrics"
echo ""
echo "Next: Configure Grafana dashboard for quantum metrics"
echo "  1. Open http://192.168.4.81:3000"
echo "  2. Login: admin / blackroad2026"
echo "  3. Add Prometheus data source: http://blackroad-prometheus:9090"
echo "  4. Import dashboard or create custom panels"
echo ""
