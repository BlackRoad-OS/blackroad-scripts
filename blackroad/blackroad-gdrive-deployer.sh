#!/bin/bash
# BlackRoad Google Drive Deployer
# Sync products to Google Drive for both accounts

PRODUCTS_DIR=~/blackroad-products
GDRIVE1="blackroad.systems@gmail.com"
GDRIVE2="amundsonalexa@gmail.com"

echo "💾 BlackRoad Google Drive Deployer"
echo "===================================="
echo ""
echo "Target accounts:"
echo "  1. $GDRIVE1"
echo "  2. $GDRIVE2"
echo ""

# Check for gdrive CLI tool
if ! command -v gdrive &> /dev/null; then
    echo "ℹ️  gdrive CLI not installed"
    echo ""
    echo "To install:"
    echo "  brew install gdrive"
    echo ""
    echo "To authenticate:"
    echo "  gdrive account add"
    echo ""
    exit 1
fi

echo "✅ gdrive CLI is installed"
echo ""

# List accounts
echo "📋 Configured accounts:"
gdrive account list || echo "No accounts configured yet"
echo ""

# Create a compressed archive of all products
ARCHIVE="~/blackroad-products-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "📦 Creating archive: $ARCHIVE"
tar -czf "$ARCHIVE" -C ~ blackroad-products/

echo "✅ Archive created: $(ls -lh "$ARCHIVE" | awk '{print $5}')"
echo ""
echo "🚀 Ready to upload to Google Drive"
echo ""
echo "To upload:"
echo "  gdrive files upload $ARCHIVE"
