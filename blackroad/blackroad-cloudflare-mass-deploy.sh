#!/bin/bash
# BlackRoad Cloudflare Mass Deployment Script
# Deploys ALL enhanced products to Cloudflare Pages

set -e

echo "🖤 BlackRoad Cloudflare Mass Deployment 🛣️"
echo ""

ENHANCEMENTS_DIR="$HOME/blackroad-enhancements"
DEPLOYED_COUNT=0

if [ ! -d "$ENHANCEMENTS_DIR" ]; then
    echo "⚠️  No enhancements directory found"
    exit 1
fi

for product_dir in "$ENHANCEMENTS_DIR"/*/; do
    if [ -d "$product_dir/ui" ]; then
        product=$(basename "$product_dir")
        project_name="blackroad-$(echo "$product" | tr '[:upper:]' '[:lower:]')"
        
        echo "🚀 Deploying $product to Cloudflare Pages..."
        
        cd "$product_dir/ui"
        
        # Deploy to Cloudflare Pages
        if wrangler pages deploy . --project-name="$project_name" --branch=main 2>/dev/null; then
            echo "✅ $product deployed: https://$project_name.pages.dev"
            DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
        else
            echo "⚠️  $product deployment needs manual setup"
        fi
        
        echo ""
    fi
done

echo "🎉 Deployed $DEPLOYED_COUNT products to Cloudflare Pages!"
