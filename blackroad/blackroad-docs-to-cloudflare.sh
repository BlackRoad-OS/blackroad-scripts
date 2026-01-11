#!/bin/bash
# Deploy BlackRoad Documentation Site to Cloudflare Pages

set -e

echo "☁️ BlackRoad Docs → Cloudflare Pages Deployment"
echo "================================================"
echo ""

DOCS_FILE=~/blackroad-docs-site/index.html
PROJECT_NAME="blackroad-docs"
DEPLOY_DIR=/tmp/blackroad-docs-deploy

if [ ! -f "$DOCS_FILE" ]; then
  echo "❌ Documentation file not found: $DOCS_FILE"
  exit 1
fi

# Create deployment directory
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Copy docs file
cp "$DOCS_FILE" "$DEPLOY_DIR/"

# Create _headers file for security
cat > "$DEPLOY_DIR/_headers" << 'HEADERSEOF'
/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  X-XSS-Protection: 1; mode=block
  Referrer-Policy: strict-origin-when-cross-origin
HEADERSEOF

# Create _redirects file
cat > "$DEPLOY_DIR/_redirects" << 'REDIRECTSEOF'
/products  /index.html#products  200
/api       /index.html#api       200
REDIRECTSEOF

echo "📦 Prepared deployment directory: $DEPLOY_DIR"
echo "📄 Files:"
ls -lh "$DEPLOY_DIR"
echo ""

# Check if project exists
if wrangler pages project list 2>/dev/null | grep -q "$PROJECT_NAME"; then
  echo "✅ Project exists: $PROJECT_NAME"
  deploy_cmd="wrangler pages deploy \"$DEPLOY_DIR\" --project-name=\"$PROJECT_NAME\""
else
  echo "🆕 Creating new project: $PROJECT_NAME"
  # For new projects, wrangler will create it automatically on first deploy
  deploy_cmd="wrangler pages deploy \"$DEPLOY_DIR\" --project-name=\"$PROJECT_NAME\""
fi

echo "🚀 Deploying to Cloudflare Pages..."
echo ""

# Deploy
if eval $deploy_cmd; then
  echo ""
  echo "🎉 DEPLOYMENT SUCCESSFUL!"
  echo "========================="
  echo ""
  echo "🌐 Your docs are live at:"
  echo "   https://$PROJECT_NAME.pages.dev"
  echo ""
  echo "📊 Cloudflare dashboard:"
  echo "   https://dash.cloudflare.com/?to=/:account/pages/view/$PROJECT_NAME"
  echo ""
  
  # Log to memory
  ~/memory-system.sh log deployed "cloudflare-docs-site" \
    "Deployed BlackRoad documentation site (16KB mega-site with 350 products) to Cloudflare Pages. Project: $PROJECT_NAME. URL: https://$PROJECT_NAME.pages.dev" \
    "blackroad-cloudflare" 2>/dev/null || true
    
else
  echo ""
  echo "❌ DEPLOYMENT FAILED"
  echo "===================="
  echo ""
  echo "Possible issues:"
  echo "  • Project limit reached (contact Cloudflare support)"
  echo "  • Authentication required (run: wrangler login)"
  echo "  • Network issues"
  echo ""
  exit 1
fi

