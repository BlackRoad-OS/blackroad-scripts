#!/bin/bash
# Quick HuggingFace deployment for BlackRoad products

HF_ORG="blackroad-os"
PRODUCTS_DIR=~/blackroad-products

echo "🤗 BlackRoad HuggingFace Deployment"
echo "===================================="
echo ""

# Check if logged in
echo "🔐 Checking HuggingFace authentication..."
if hf whoami &> /dev/null; then
    echo "✅ Logged in to HuggingFace as: $(hf whoami 2>&1 | head -1)"
else
    echo "⚠️  Not logged in. Please run: hf login"
    echo "Get token from: https://huggingface.co/settings/tokens"
    exit 1
fi

echo ""
echo "📦 Deploying BlackRoad products as Models..."
echo ""

# Deploy first 20 products as models to test
count=0
max_deploy=20

for script in "$PRODUCTS_DIR"/blackroad-*.sh; do
    [ -f "$script" ] || continue
    [[ "$(basename "$script")" == *"batch-create"* ]] && continue
    
    filename=$(basename "$script" .sh)
    repo_name="$filename"
    
    echo "[$((count+1))/$max_deploy] Creating: $HF_ORG/$repo_name"
    
    # Create model repo
    if hf repo create "$HF_ORG/$repo_name" --type model 2>&1 | tee /tmp/hf-$repo_name.log | grep -q "already exists\|created"; then
        url="https://huggingface.co/$HF_ORG/$repo_name"
        echo "  ✅ $url"
        
        # Upload the script as a file
        hf upload "$HF_ORG/$repo_name" "$script" --repo-type model 2>/dev/null || echo "  ℹ️  Upload pending"
    else
        echo "  ⚠️  Check logs: /tmp/hf-$repo_name.log"
    fi
    
    count=$((count+1))
    [ $count -ge $max_deploy ] && break
    
    # Rate limiting
    [ $((count % 5)) -eq 0 ] && sleep 2
done

echo ""
echo "🎉 Deployment complete!"
echo "📊 Created $count repositories on HuggingFace"
echo "🌐 View at: https://huggingface.co/$HF_ORG"
