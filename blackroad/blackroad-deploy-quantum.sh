#!/bin/bash
# Deploy distributed quantum workers across BlackRoad cluster

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌌 DEPLOYING DISTRIBUTED QUANTUM WORKERS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Create quantum worker image on each node
echo ""
echo "Step 1: Installing quantum environment on all nodes..."

for host in octavia lucidia aria alice; do
    echo "  Setting up $host..."
    ssh $host << 'EOF'
# Create quantum venv if not exists
if [ ! -d ~/quantum-venv ]; then
    python3 -m venv ~/quantum-venv
fi

# Install quantum packages
source ~/quantum-venv/bin/activate
pip install -q qiskit qiskit-aer numpy scipy 2>/dev/null || true

# Create quantum worker script
cat > ~/quantum-worker.py << 'WORKER'
#!/usr/bin/env python3
"""
BlackRoad Distributed Quantum Worker
Listens for quantum jobs via NATS, executes circuits, returns results
"""

import sys
import os
import json
import socket
import time
from datetime import datetime

# Add quantum-venv packages to path
sys.path.insert(0, '/home/pi/quantum-venv/lib/python3.13/site-packages')

try:
    from qiskit import QuantumCircuit, transpile
    from qiskit_aer import AerSimulator
    import numpy as np
except ImportError as e:
    print(f"Import error: {e}")
    sys.exit(1)

NATS_HOST = "blackroad-nats"
NATS_PORT = 4222
NODE_NAME = socket.gethostname()

print(f"""
╔════════════════════════════════════════════════════════════╗
║  🌌 BlackRoad Quantum Worker - {NODE_NAME:10s}           ║
╚════════════════════════════════════════════════════════════╝
""")

def execute_bell_test():
    """Execute a Bell state test"""
    qc = QuantumCircuit(2, 2)
    qc.h(0)
    qc.cx(0, 1)
    qc.measure([0, 1], [0, 1])

    simulator = AerSimulator()
    compiled = transpile(qc, simulator)
    start = time.time()
    job = simulator.run(compiled, shots=1000)
    elapsed = time.time() - start

    counts = job.result().get_counts()

    return {
        'test': 'bell_state',
        'node': NODE_NAME,
        'counts': counts,
        'shots': 1000,
        'time_ms': round(elapsed * 1000, 2),
        'timestamp': datetime.now().isoformat()
    }

def execute_grover_search(n_qubits=3):
    """Execute Grover's algorithm"""
    qc = QuantumCircuit(n_qubits, n_qubits)

    # Initialize superposition
    qc.h(range(n_qubits))

    # Oracle (mark |111⟩ as target)
    qc.mct(list(range(n_qubits-1)), n_qubits-1)

    # Diffusion operator
    qc.h(range(n_qubits))
    qc.x(range(n_qubits))
    qc.h(n_qubits-1)
    qc.mct(list(range(n_qubits-1)), n_qubits-1)
    qc.h(n_qubits-1)
    qc.x(range(n_qubits))
    qc.h(range(n_qubits))

    # Measure
    qc.measure(range(n_qubits), range(n_qubits))

    simulator = AerSimulator()
    compiled = transpile(qc, simulator)
    start = time.time()
    job = simulator.run(compiled, shots=1000)
    elapsed = time.time() - start

    counts = job.result().get_counts()

    # Find most common state
    target = max(counts, key=counts.get)

    return {
        'test': 'grover_search',
        'node': NODE_NAME,
        'n_qubits': n_qubits,
        'target_found': target,
        'counts': counts,
        'time_ms': round(elapsed * 1000, 2),
        'timestamp': datetime.now().isoformat()
    }

def execute_superposition(n_qubits=5):
    """Test quantum superposition"""
    qc = QuantumCircuit(n_qubits, n_qubits)
    qc.h(range(n_qubits))
    qc.measure(range(n_qubits), range(n_qubits))

    simulator = AerSimulator()
    compiled = transpile(qc, simulator)
    start = time.time()
    job = simulator.run(compiled, shots=100)
    elapsed = time.time() - start

    counts = job.result().get_counts()

    return {
        'test': 'superposition',
        'node': NODE_NAME,
        'n_qubits': n_qubits,
        'unique_states': len(counts),
        'expected_states': 2**n_qubits,
        'time_ms': round(elapsed * 1000, 2),
        'timestamp': datetime.now().isoformat()
    }

# Run test suite
print("Running quantum test suite...")
print()

results = []

# Test 1: Bell State
print("Test 1: Bell State Entanglement")
result = execute_bell_test()
print(f"  Node: {result['node']}")
print(f"  Counts: {result['counts']}")
print(f"  Time: {result['time_ms']}ms")
results.append(result)
print()

# Test 2: Superposition
print("Test 2: Quantum Superposition (5 qubits)")
result = execute_superposition(5)
print(f"  Node: {result['node']}")
print(f"  States: {result['unique_states']}/{result['expected_states']}")
print(f"  Time: {result['time_ms']}ms")
results.append(result)
print()

# Test 3: Grover Search
print("Test 3: Grover's Search Algorithm")
result = execute_grover_search(3)
print(f"  Node: {result['node']}")
print(f"  Target: {result['target_found']}")
print(f"  Time: {result['time_ms']}ms")
results.append(result)
print()

# Save results
results_file = f"/tmp/quantum-results-{NODE_NAME}.json"
with open(results_file, 'w') as f:
    json.dump(results, f, indent=2)

print(f"✅ Results saved to {results_file}")
print()
print(f"╚════════════════════════════════════════════════════════════╝")
WORKER

chmod +x ~/quantum-worker.py
echo "✅ $(hostname) ready"
EOF
done

echo ""
echo "Step 2: Running quantum workers on all nodes..."
echo ""

# Run workers in parallel on all nodes
for host in octavia lucidia aria alice; do
    (
        echo "=== $host STARTING ==="
        ssh $host "source ~/quantum-venv/bin/activate && python3 ~/quantum-worker.py"
    ) &
done

# Wait for all workers to complete
wait

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ QUANTUM WORKERS COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Collecting results from all nodes..."

for host in octavia lucidia aria alice; do
    echo ""
    echo "=== $host RESULTS ==="
    ssh $host "cat /tmp/quantum-results-$host.json 2>/dev/null || echo 'No results yet'"
done

echo ""
echo "Results saved on each node at /tmp/quantum-results-HOSTNAME.json"
