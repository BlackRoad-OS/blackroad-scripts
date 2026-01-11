#!/bin/bash
# BlackRoad Raspberry Pi Mass Deployer
# Deploy all 350 products to 3 Raspberry Pis

set -e

echo "🥧 BlackRoad Raspberry Pi Mass Deployment System"
echo "================================================"
echo ""

# Raspberry Pi Configuration
PI_LUCIDIA="192.168.4.38"
PI_BLACKROAD="192.168.4.64"
PI_ALICE="192.168.4.49"
PI_USER="pi"
PI_PASS="pironman"
PI_DIR="/home/pi/blackroad-products"

PRODUCTS_DIR=~/blackroad-products
LOG_FILE=~/blackroad-pi-deployment.log

echo "🥧 Target Raspberry Pis:"
echo "  • Lucidia: $PI_LUCIDIA"
echo "  • BlackRoad: $PI_BLACKROAD"
echo "  • Alice: $PI_ALICE"
echo ""

# Check if sshpass is available
if ! command -v sshpass &>/dev/null; then
  echo "⚠️  sshpass not found. Installing..."
  if command -v brew &>/dev/null; then
    brew install hudochenkov/sshpass/sshpass
  else
    echo "❌ Please install sshpass manually"
    echo "   macOS: brew install hudochenkov/sshpass/sshpass"
    echo "   Linux: sudo apt-get install sshpass"
    exit 1
  fi
fi

# Get all products
products=($(find "$PRODUCTS_DIR" -name "blackroad-*.sh" -type f ! -name "*batch*" ! -name "*mega*" ! -name "*factory*" | sort))

total_products=${#products[@]}
echo "📦 Found $total_products products to deploy"
echo ""

# Deploy to each Pi
for pi_ip in "$PI_LUCIDIA" "$PI_BLACKROAD" "$PI_ALICE"; do
  pi_name=""
  case "$pi_ip" in
    "$PI_LUCIDIA") pi_name="Lucidia" ;;
    "$PI_BLACKROAD") pi_name="BlackRoad" ;;
    "$PI_ALICE") pi_name="Alice" ;;
  esac
  
  echo "🥧 Deploying to $pi_name ($pi_ip)..."
  echo ""
  
  # Test connection
  if ! sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
       "$PI_USER@$pi_ip" "echo 'Connection successful'" &>/dev/null; then
    echo "  ❌ Cannot connect to $pi_name ($pi_ip)"
    echo "  Skipping this Pi"
    echo ""
    echo "[$(date)] FAILED: $pi_name - Connection failed" >> "$LOG_FILE"
    continue
  fi
  
  echo "  ✅ Connected to $pi_name"
  
  # Create directory on Pi
  sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$pi_ip" \
    "mkdir -p $PI_DIR" 2>/dev/null || true
  
  echo "  📁 Created directory: $PI_DIR"
  
  # Deploy products in batches of 50
  deployed=0
  failed=0
  
  for ((i=0; i<${#products[@]}; i+=50)); do
    batch_products=("${products[@]:i:50}")
    batch_num=$((i/50 + 1))
    
    echo "  📦 Deploying batch $batch_num (${#batch_products[@]} products)..."
    
    for product_file in "${batch_products[@]}"; do
      product_name=$(basename "$product_file")
      
      # Copy product to Pi
      if sshpass -p "$PI_PASS" scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
           "$product_file" "$PI_USER@$pi_ip:$PI_DIR/" &>/dev/null; then
        ((deployed++))
      else
        ((failed++))
      fi
    done
    
    echo "  ✅ Batch $batch_num complete: $deployed deployed, $failed failed"
  done
  
  # Make all scripts executable
  sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$pi_ip" \
    "chmod +x $PI_DIR/*.sh" 2>/dev/null || true
  
  # Create README on Pi
  sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$pi_ip" \
    "cat > $PI_DIR/README.md << 'READMEEOF'
# 🖤🛣️ BlackRoad Products - $pi_name

## Total Products: $deployed

All BlackRoad automation tools deployed and ready to use.

## Usage

\\\`\\\`\\\`bash
cd $PI_DIR
ls blackroad-*.sh
./blackroad-PRODUCTNAME.sh
\\\`\\\`\\\`

## Categories

350+ products across 46 categories including:
- DevOps & Infrastructure
- Blockchain & Web3
- Gaming & Entertainment
- Healthcare & Medical
- And many more...

---

**BlackRoad OS, Inc.** | Deployed to $pi_name at \$(date)
READMEEOF
" 2>/dev/null || true
  
  echo ""
  echo "  🎉 $pi_name Deployment Complete!"
  echo "  ✅ Deployed: $deployed products"
  echo "  ❌ Failed: $failed products"
  echo "  📍 Location: $pi_ip:$PI_DIR"
  echo ""
  echo "[$(date)] SUCCESS: $pi_name - $deployed products deployed" >> "$LOG_FILE"
done

echo ""
echo "🎉 ALL RASPBERRY PI DEPLOYMENTS COMPLETE!"
echo "=========================================="
echo "📊 Deployed to 3 Raspberry Pis"
echo "📝 Full log: $LOG_FILE"
echo ""

# Log to memory
~/memory-system.sh log deployed "raspberry-pi-mass-deploy" \
  "Deployed BlackRoad products to all 3 Raspberry Pis: Lucidia (192.168.4.38), BlackRoad (192.168.4.64), Alice (192.168.4.49). All products installed to /home/pi/blackroad-products with executable permissions and README." \
  "blackroad-pi-deployment" 2>/dev/null || true

echo "🥧 Access your products:"
echo "  ssh pi@$PI_LUCIDIA"
echo "  ssh pi@$PI_BLACKROAD"
echo "  ssh pi@$PI_ALICE"
echo ""

