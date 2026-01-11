#!/bin/bash
# BlackRoad HuggingFace Smart Deployer
# Automatically finds credentials and deploys all 400 products

set -e

echo "🤗 BlackRoad HuggingFace Smart Deployment System"
echo "================================================="
echo ""

PRODUCTS_DIR=~/blackroad-products
DEPLOY_DIR=/tmp/hf-blackroad-smart-deploy
LOG_FILE=~/blackroad-hf-deployment.log

mkdir -p "$DEPLOY_DIR"

# Check for HF authentication - multiple methods
echo "🔍 Checking for HuggingFace credentials..."
echo ""

HF_TOKEN=""

# Method 1: Check environment variable
if [ -n "$HUGGINGFACE_API_KEY" ]; then
  echo "✅ Found HUGGINGFACE_API_KEY in environment"
  HF_TOKEN="$HUGGINGFACE_API_KEY"
elif [ -n "$HF_TOKEN" ]; then
  echo "✅ Found HF_TOKEN in environment"
fi

# Method 2: Check secrets file
if [ -z "$HF_TOKEN" ] && [ -f ~/.blackroad/secrets.env ]; then
  TOKEN_FROM_FILE=$(grep "HUGGINGFACE_API_KEY\|HF_TOKEN" ~/.blackroad/secrets.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' | head -1)
  if [ -n "$TOKEN_FROM_FILE" ]; then
    echo "✅ Found token in ~/.blackroad/secrets.env"
    HF_TOKEN="$TOKEN_FROM_FILE"
  fi
fi

# Method 3: Check if already logged in via HF CLI
if [ -z "$HF_TOKEN" ]; then
  if hf auth whoami &>/dev/null; then
    echo "✅ Already logged in to HuggingFace CLI"
    HF_LOGGED_IN=true
  fi
fi

# Method 4: Try to use huggingface_hub Python package
if [ -z "$HF_TOKEN" ] && [ -z "$HF_LOGGED_IN" ]; then
  PYTHON_TOKEN=$(python3 -c "
try:
    from huggingface_hub import HfFolder
    token = HfFolder.get_token()
    print(token if token else '')
except:
    pass
" 2>/dev/null)
  
  if [ -n "$PYTHON_TOKEN" ]; then
    echo "✅ Found token via huggingface_hub Python package"
    HF_TOKEN="$PYTHON_TOKEN"
  fi
fi

echo ""

# If we have a token, log in with it
if [ -n "$HF_TOKEN" ]; then
  echo "🔐 Logging in to HuggingFace..."
  echo "$HF_TOKEN" | hf auth login --token-stdin 2>/dev/null || true
  echo ""
fi

# Final check
if ! hf auth whoami &>/dev/null; then
  echo "❌ No HuggingFace credentials found!"
  echo ""
  echo "Please provide credentials via one of these methods:"
  echo "  1. Run: hf auth login"
  echo "  2. Set env var: export HUGGINGFACE_API_KEY=your_token"
  echo "  3. Create ~/.blackroad/secrets.env with: HUGGINGFACE_API_KEY=your_token"
  echo ""
  echo "Get token from: https://huggingface.co/settings/tokens"
  echo ""
  exit 1
fi

HF_USER=$(hf auth whoami 2>&1 | head -1)
echo "🤗 Logged in as: $HF_USER"
echo ""

# Get all products
products=($(find "$PRODUCTS_DIR" -name "blackroad-*.sh" -type f ! -name "*batch*" ! -name "*mega*" ! -name "*factory*" | sort))

total_products=${#products[@]}
deployed=0
failed=0
skipped=0

echo "📦 Found $total_products products to deploy"
echo "⏰ Starting deployment at $(date)"
echo ""

# Deploy in batches of 10 to avoid rate limiting
batch_size=10
batch_num=0

for ((i=0; i<${#products[@]}; i+=batch_size)); do
  ((batch_num++))
  batch_products=("${products[@]:i:batch_size}")
  
  echo "📦 Batch $batch_num: Processing ${#batch_products[@]} products..."
  
  for product_file in "${batch_products[@]}"; do
    product_basename=$(basename "$product_file" .sh)
    product_name=${product_basename#blackroad-}
    repo_name="blackroad-$product_name"
    
    # Check if repo already exists
    if hf repo info "$HF_USER/$repo_name" &>/dev/null; then
      ((skipped++))
      echo "  ⏭️  $repo_name - Already exists"
      continue
    fi
    
    # Create staging directory
    staging_dir="$DEPLOY_DIR/$repo_name"
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    
    # Copy product file
    cp "$product_file" "$staging_dir/"
    
    # Create comprehensive README/Model Card
    cat > "$staging_dir/README.md" << EOF
---
license: mit
tags:
  - blackroad
  - enterprise
  - automation
  - ${product_name}
  - devops
  - infrastructure
---

# 🖤🛣️ BlackRoad $(echo $product_name | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

**Part of the BlackRoad Product Empire** - 400+ enterprise automation solutions

## 🚀 Quick Start

\`\`\`bash
# Download from HuggingFace
huggingface-cli download $HF_USER/$repo_name

# Make executable and run
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

This is one of **400+ products** spanning 52 categories:
🔗 Blockchain & Web3 | 🎮 Gaming | 🏥 Healthcare | 📚 Education | 🌐 IoT  
🛒 E-Commerce | 📱 Mobile & APIs | 🏢 Enterprise | 🏠 Real Estate | 🌾 Agriculture  
⚖️ Legal | 🏭 Manufacturing | ✈️ Travel | 🏛️ Government | 🎬 Media  
⚽ Sports | 🚗 Automotive | ⚡ Energy | 💝 Social Impact | 🚀 Space  
🤖 Robotics | ⚛️ Quantum Computing | 📡 Telecom | 🧬 Biotech | 🛡️ Defense  
🌦️ Weather & Climate | 🥽 VR/AR | ☢️ Advanced Energy | ⚗️ Nanotechnology  
🌊 Marine Tech | 💰 FinTech | 🏙️ Smart Cities | 🤖 AI & ML | ⚙️ DevOps & SRE  
⛓️ Web3 & Decentralized | 📊 Data Engineering | 🔐 Cybersecurity | 🌐 Edge Computing

## 🖤 Built by BlackRoad

**BlackRoad OS, Inc.** | Powered by AI | Built with ∞ vision

---

*Generated and deployed via automated CI/CD pipeline*
EOF
    
    # Upload to HuggingFace
    if hf upload "$HF_USER/$repo_name" "$staging_dir" --create --repo-type model 2>&1 | tee -a "$LOG_FILE" | grep -q "success\|uploaded\|created"; then
      echo "  ✅ $repo_name - SUCCESS!"
      ((deployed++))
    else
      echo "  ❌ $repo_name - FAILED"
      ((failed++))
    fi
    
    # Small delay
    sleep 1
  done
  
  echo ""
  echo "  Batch $batch_num complete: $deployed total deployed, $skipped skipped, $failed failed"
  echo ""
  
  # Delay between batches to avoid rate limiting
  if [ $i -lt $((total_products - batch_size)) ]; then
    echo "  ⏸️  Pausing 10 seconds between batches..."
    sleep 10
  fi
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

# Log to memory
if [ $deployed -gt 0 ]; then
  ~/memory-system.sh log deployed "huggingface-smart-deploy-$deployed" \
    "Deployed $deployed BlackRoad products to HuggingFace Hub as $HF_USER using smart credential detection. Total: $deployed deployed, $skipped already existed, $failed failed. All products include comprehensive model cards with BlackRoad branding, documentation links, and proper metadata. Multi-method auth: env vars, secrets file, HF CLI, Python package." \
    "blackroad-huggingface" 2>/dev/null || true
fi

echo "🤗 View your models at: https://huggingface.co/$HF_USER"
echo ""

