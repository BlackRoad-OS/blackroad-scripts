#!/bin/bash
# Simple BlackRoad Deployment Script

echo "🌌 BlackRoad Empire Deployment"
echo ""

# Test wrangler
if command -v wrangler &> /dev/null; then
    echo "✅ Wrangler installed"
    wrangler whoami
else
    echo "❌ Wrangler not installed"
fi

# Test gh
if command -v gh &> /dev/null; then
    echo "✅ GitHub CLI installed"
    gh auth status 2>&1 | head -3
else
    echo "❌ GitHub CLI not installed"
fi

# Check files
echo ""
echo "📁 Files:"
[ -f ~/Desktop/blackroad-os-ultimate-modern.html ] && echo "✅ OS file found" || echo "❌ OS file not found"
[ -f ~/Desktop/lucidia-minnesota-wilderness\(1\).html ] && echo "✅ Lucidia file found" || echo "❌ Lucidia file not found"

echo ""
echo "🚀 Ready to deploy!"
