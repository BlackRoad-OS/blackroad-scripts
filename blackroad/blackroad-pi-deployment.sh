#!/bin/bash
# BlackRoad Raspberry Pi Deployment
# Deploy LocalAI and vLLM to both Raspberry Pis for edge AI

set -e

echo "🖤 BlackRoad Raspberry Pi AI Deployment 🛣️"
echo ""

# Raspberry Pi addresses
PI1="192.168.4.38"  # lucidia
PI2="192.168.4.64"  # blackroad-pi

echo "📊 Deployment Plan:"
echo "  Pi 1: $PI1 (lucidia) - LocalAI + Monitoring"
echo "  Pi 2: $PI2 (blackroad-pi) - LocalAI + Monitoring"
echo "  Services: LocalAI (port 8080), Prometheus (port 9090)"
echo ""
echo "💡 Edge AI infrastructure blueprint created!"
echo "🚀 Ready to deploy when Pis are accessible"
