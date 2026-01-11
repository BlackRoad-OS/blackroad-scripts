#!/bin/bash
# BlackRoad HuggingFace Mass Deployer - Deploy all 350 products to HF Hub
# Usage: ./blackroad-hf-mass-deployer.sh

set -e

echo "🤗 BlackRoad HuggingFace Mass Deployment System"
echo "==============================================="
echo ""

# Check if logged in
if ! hf auth whoami &>/dev/null; then
  echo "❌ Not logged in to HuggingFace!"
  echo ""
  echo "Please run: hf auth login"
  echo "Get token from: https://huggingface.co/settings/tokens"
  echo ""
  exit 1
fi

HF_USER=$(hf auth whoami 2>&1 | grep -v "Logged in" | head -1)
PRODUCTS_DIR=~/blackroad-products
DEPLOY_DIR=/tmp/hf-blackroad-deploy
LOG_FILE=~/blackroad-hf-deployment.log

mkdir -p "$DEPLOY_DIR"

echo "🤗 Logged in as: $HF_USER"
echo "📦 Deploying BlackRoad products to HuggingFace Hub"
echo ""

# Get all products
products=($(find "$PRODUCTS_DIR" -name "blackroad-*.sh" -type f ! -name "*batch*" ! -name "*mega*" ! -name "*factory*" | sort))

total_products=${#products[@]}
deployed=0
failed=0
skipped=0

echo "📊 Found $total_products products to deploy"
echo "⏰ Starting deployment at $(date)"
echo ""

for product_file in "${products[@]}"; do
  product_basename=$(basename "$product_file" .sh)
  product_name=${product_basename#blackroad-}
  repo_name="blackroad-$product_name"
  
  echo "[$((deployed + failed + skipped + 1))/$total_products] Processing: $repo_name"
  
  # Check if repo already exists
  if hf repo info "$HF_USER/$repo_name" &>/dev/null; then
    echo "  ⏭️  Already exists, skipping"
    ((skipped++))
    echo "" >> "$LOG_FILE"
    echo "[$(date)] SKIPPED: $repo_name (already exists)" >> "$LOG_FILE"
    continue
  fi
  
  # Create staging directory
  staging_dir="$DEPLOY_DIR/$repo_name"
  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  
  # Copy product file
  cp "$product_file" "$staging_dir/"
  
  # Create README.md (Model Card)
  cat > "$staging_dir/README.md" << EOF
---
license: mit
tags:
  - blackroad
  - enterprise
  - automation
  - ${product_name}
---

# 🖤🛣️ BlackRoad $(echo $product_name | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

Part of the **BlackRoad Product Empire** - 350+ enterprise automation solutions

## 🚀 Quick Start

\`\`\`bash
# Download and run
huggingface-cli download $HF_USER/$repo_name
chmod +x blackroad-${product_name}.sh
./blackroad-${product_name}.sh
\`\`\`

## 📋 Description

BlackRoad $(echo $product_name | tr '-' ' ') is an enterprise-grade automation solution designed for maximum efficiency and scalability.

## 🎨 BlackRoad Design System

- **Hot Pink**: #FF1D6C
- **Amber**: #F5A623
- **Electric Blue**: #2979FF  
- **Violet**: #9C27B0
- **Golden Ratio**: φ = 1.618

## 🌐 Links

- **GitHub**: https://github.com/BlackRoad-OS/$repo_name
- **Documentation**: https://docs.blackroad.io
- **Website**: https://blackroad.io

## 📦 Part of BlackRoad Empire

This is one of **350+ products** spanning 46 categories:
- 🔗 Blockchain & Web3
- 🎮 Gaming & Entertainment
- 🏥 Healthcare & Medical
- 📚 Education & Learning
- 🌐 IoT & Hardware
- 🛒 E-Commerce & Retail
- 📱 Mobile & APIs
- 🏢 Enterprise & Business
- 🏠 Real Estate & Property
- 🌾 Agriculture & Environment
- ⚖️ Legal & Compliance
- 🏭 Manufacturing & Industrial
- ✈️ Travel & Hospitality
- 🏛️ Government & Public Sector
- 🎬 Media & Broadcasting
- ⚽ Sports & Fitness
- 🚗 Automotive & Transportation
- ⚡ Energy & Utilities
- 💝 Non-Profit & Social Impact
- 🚀 Space & Aerospace
- 🤖 Robotics & Automation
- ⚛️ Quantum Computing
- 📡 Telecommunications
- 🧬 Biotechnology
- 🛡️ Defense & Security
- 🌦️ Weather & Climate
- 🥽 VR/AR & Metaverse
- ☢️ Advanced Energy
- ⚗️ Nanotechnology
- 🌊 Marine & Ocean Tech
- 💰 FinTech & Banking
- 🏙️ Smart Cities

## 🖤 Built by BlackRoad

**BlackRoad OS, Inc.** | Powered by AI | Built with ∞ vision

---

*Generated and deployed via automated CI/CD pipeline*
EOF
  
  # Create requirements.txt (optional, for compatibility)
  cat > "$staging_dir/requirements.txt" << EOF
# No dependencies required - pure bash automation
EOF
  
  # Try to create the repo and upload
  if hf repo create --type model "$repo_name" 2>/dev/null; then
    echo "  ✅ Created repo: $HF_USER/$repo_name"
    
    # Upload files
    if hf upload "$HF_USER/$repo_name" "$staging_dir" --repo-type model 2>/dev/null; then
      echo "  📤 Uploaded files successfully"
      ((deployed++))
      echo "[$(date)] SUCCESS: $repo_name" >> "$LOG_FILE"
    else
      echo "  ❌ Upload failed"
      ((failed++))
      echo "[$(date)] FAILED: $repo_name (upload error)" >> "$LOG_FILE"
    fi
  else
    echo "  ❌ Failed to create repo"
    ((failed++))
    echo "[$(date)] FAILED: $repo_name (repo creation error)" >> "$LOG_FILE"
  fi
  
  # Small delay to avoid rate limiting
  sleep 2
  
  echo ""
done

echo ""
echo "🎉 HUGGINGFACE DEPLOYMENT COMPLETE!"
echo "===================================="
echo "✅ Successfully deployed: $deployed"
echo "⏭️  Skipped (existing): $skipped"
echo "❌ Failed: $failed"
echo "📊 Total processed: $total_products"
echo ""
echo "📝 Full log: $LOG_FILE"
echo ""

# Summary to memory
if [ $deployed -gt 0 ]; then
  ~/memory-system.sh log deployed "huggingface-mass-deploy-$deployed" \
    "Deployed $deployed BlackRoad products to HuggingFace Hub as $HF_USER. Total: $deployed deployed, $skipped already existed, $failed failed. All products include model cards with BlackRoad branding, documentation links, and proper metadata." \
    "blackroad-huggingface" 2>/dev/null || true
fi

echo "🤗 View your models at: https://huggingface.co/$HF_USER"
echo ""

