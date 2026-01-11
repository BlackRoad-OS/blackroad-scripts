#!/bin/bash
# BlackRoad Execution Tracker - Monitor deployment progress

echo "🖤 BlackRoad Execution Tracker 🛣️"
echo ""

# Check GitHub repos
echo "📊 GitHub Status:"
gh repo list BlackRoad-OS --limit 200 --json name,isPrivate | jq -r '.[] | "\(.name) - \(if .isPrivate then "Private" else "Public" end)"' | grep "blackroad-" | wc -l | xargs echo "  Repos with 'blackroad-':"

# Check enhanced products
echo ""
echo "📦 Enhanced Products:"
if [ -d ~/blackroad-enhancements ]; then
    find ~/blackroad-enhancements -maxdepth 1 -type d | tail -n +2 | wc -l | xargs echo "  Total enhanced:"
fi

# Check marketplace
echo ""
echo "📋 Task Marketplace:"
~/memory-task-marketplace.sh stats 2>/dev/null | grep "Total Tasks" || echo "  (run stats manually)"

# Check memory
echo ""
echo "🧠 Memory System:"
~/memory-system.sh summary 2>/dev/null | grep "Total entries" || echo "  (active)"

echo ""
echo "✅ Run individual scripts to deploy:"
echo "   ~/blackroad-cloudflare-mass-deploy.sh"
echo "   ~/push-all-enhanced-to-github.sh"
echo "   ~/blackroad-pi-deployment.sh"
