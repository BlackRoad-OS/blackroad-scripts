#!/bin/bash
# 🚀 BlackRoad Autopilot - Run this daily

# Monitor and merge PRs
echo "🔀 Checking PRs..."
~/pr-monitor.sh
DRY_RUN=false ~/pr-auto-merge.sh

# Update all repos
echo "📦 Syncing repos..."
for org in BlackRoad-OS BlackRoad-AI; do
  gh repo list $org --limit 100 --json name -q '.[].name' | while read repo; do
    echo "  → $repo"
  done
done

# Check agent status
echo "🤖 Agent status..."
~/memory-collaboration-dashboard.sh compact

# Update leaderboard
echo "🏆 Leaderboard..."
~/blackroad-agent-leaderboard.sh show | head -10

echo ""
echo "✅ Autopilot complete!"
