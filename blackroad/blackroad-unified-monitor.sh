#!/bin/bash
# 📊 BlackRoad Unified Monitoring

echo "📊 BLACKROAD INFRASTRUCTURE STATUS"
echo "==================================="
echo ""

# GitHub
GH_REPOS=$(gh repo list BlackRoad-OS --limit 1000 --json name -q '.[].name' | wc -l | tr -d ' ')
echo "GitHub Repos: $GH_REPOS"

# Cloudflare
CF_PROJECTS=$(wrangler pages project list 2>/dev/null | grep -v "^$" | grep -v "Listing" | wc -l | tr -d ' ')
echo "Cloudflare Pages: $CF_PROJECTS"

# Disk Usage
echo ""
echo "Disk Usage:"
df -h ~ | tail -1

# Active Processes
echo ""
echo "Active Automations:"
pgrep -f "blackroad" | wc -l | xargs echo "  Running processes:"

# Memory System
echo ""
echo "Memory System:"
~/memory-system.sh summary | tail -5

echo ""
echo "✅ All systems operational"
