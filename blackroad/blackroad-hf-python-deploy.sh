#!/bin/bash
# BlackRoad HuggingFace Python API Deployment
# Uses Python huggingface_hub to properly create repos

set -e

echo "🤗 BlackRoad HuggingFace Python Deployment System"
echo "=================================================="
echo ""

PRODUCTS_DIR=~/blackroad-products
DEPLOY_DIR=/tmp/hf-blackroad-python-deploy
LOG_FILE=~/blackroad-hf-python-deployment.log

mkdir -p "$DEPLOY_DIR"

# HuggingFace token from previous authentication
HF_TOKEN="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"

echo "🔐 Authenticating with HuggingFace..."
export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
export HF_TOKEN="$HF_TOKEN"

# Create Python deployment script
cat > /tmp/hf_deploy_product.py << 'PYEOF'
import sys
import os
from pathlib import Path
from huggingface_hub import HfApi, create_repo, upload_folder, login

def deploy_product(product_file, hf_token, username="blackroadio"):
    """Deploy a single product to HuggingFace"""
    
    # Login
    login(token=hf_token)
    api = HfApi()
    
    # Extract product name
    product_basename = Path(product_file).stem
    product_name = product_basename.replace("blackroad-", "")
    repo_name = f"blackroad-{product_name}"
    repo_id = f"{username}/{repo_name}"
    
    # Check if repo exists
    try:
        api.repo_info(repo_id=repo_id, repo_type="model")
        print(f"⏭️  {repo_name} - Already exists")
        return "skipped"
    except:
        pass  # Repo doesn't exist, create it
    
    # Create staging directory
    staging_dir = Path(f"/tmp/hf-deploy-{repo_name}")
    staging_dir.mkdir(parents=True, exist_ok=True)
    
    # Copy product file
    import shutil
    shutil.copy(product_file, staging_dir / Path(product_file).name)
    
    # Create README with model card
    product_title = product_name.replace('-', ' ').title()
    
    readme_content = f"""---
license: mit
tags:
  - blackroad
  - enterprise
  - automation
  - {product_name}
  - devops
  - infrastructure
---

# 🖤🛣️ BlackRoad {product_title}

**Part of the BlackRoad Product Empire** - 400+ enterprise automation solutions

## 🚀 Quick Start

```bash
# Download from HuggingFace
huggingface-cli download {repo_id}

# Make executable and run
chmod +x blackroad-{product_name}.sh
./blackroad-{product_name}.sh
```

## 📋 Description

BlackRoad {product_name.replace('-', ' ')} is an enterprise-grade automation solution designed for maximum efficiency and scalability.

## 🎨 BlackRoad Design System

- **Hot Pink**: #FF1D6C  
- **Amber**: #F5A623
- **Electric Blue**: #2979FF
- **Violet**: #9C27B0
- **Golden Ratio**: φ = 1.618

## 🌐 Links

- **GitHub**: https://github.com/BlackRoad-OS/{repo_name}
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
"""
    
    with open(staging_dir / "README.md", "w") as f:
        f.write(readme_content)
    
    try:
        # Create the repository
        create_repo(
            repo_id=repo_id,
            repo_type="model",
            private=False,
            token=hf_token
        )
        
        # Upload all files
        upload_folder(
            folder_path=str(staging_dir),
            repo_id=repo_id,
            repo_type="model",
            token=hf_token
        )
        
        print(f"✅ {repo_name} - SUCCESS!")
        return "deployed"
        
    except Exception as e:
        print(f"❌ {repo_name} - FAILED: {str(e)}")
        return "failed"

if __name__ == "__main__":
    product_file = sys.argv[1]
    hf_token = sys.argv[2]
    result = deploy_product(product_file, hf_token)
    sys.exit(0 if result != "failed" else 1)
PYEOF

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
    
    # Deploy using Python
    if python3 /tmp/hf_deploy_product.py "$product_file" "$HF_TOKEN" 2>&1 | tee -a "$LOG_FILE"; then
      result=$(tail -1 "$LOG_FILE")
      if echo "$result" | grep -q "SUCCESS"; then
        ((deployed++))
      elif echo "$result" | grep -q "Already exists"; then
        ((skipped++))
      else
        ((failed++))
      fi
    else
      ((failed++))
    fi
    
    # Small delay to avoid rate limiting
    sleep 2
  done
  
  echo ""
  echo "  Batch $batch_num complete: $deployed deployed, $skipped skipped, $failed failed"
  echo ""
  
  # Delay between batches
  if [ $i -lt $((total_products - batch_size)) ]; then
    echo "  ⏸️  Pausing 15 seconds between batches..."
    sleep 15
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
  ~/memory-system.sh log deployed "huggingface-python-deploy-$deployed" \
    "Deployed $deployed BlackRoad products to HuggingFace Hub using Python huggingface_hub API. Total: $deployed deployed, $skipped already existed, $failed failed. All repos created with comprehensive model cards, BlackRoad branding, and proper metadata. Used create_repo + upload_folder for proper repo creation." \
    "blackroad-huggingface" 2>/dev/null || true
fi

echo "🤗 View your models at: https://huggingface.co/blackroadio"
echo ""

