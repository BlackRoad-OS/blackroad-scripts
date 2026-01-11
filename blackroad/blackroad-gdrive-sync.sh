#!/bin/bash
# BlackRoad Google Drive Auto-Sync

BACKUP_DIR="/tmp/blackroad-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "🖤 BlackRoad Google Drive Backup 🛣️"
echo ""
echo "📦 Creating backup package..."

# Backup critical files
[ -d ~/blackroad-api-gateway ] && cp -r ~/blackroad-api-gateway "$BACKUP_DIR/"
[ -d ~/blackroad-react-components ] && cp -r ~/blackroad-react-components "$BACKUP_DIR/"
[ -d ~/blackroad-enhancements ] && cp -r ~/blackroad-enhancements "$BACKUP_DIR/"

# Backup documentation
cp ~/BLACKROAD_*.md "$BACKUP_DIR/" 2>/dev/null || true
cp ~/SESSION_*.md "$BACKUP_DIR/" 2>/dev/null || true
cp ~/PROPRIETARY_*.md "$BACKUP_DIR/" 2>/dev/null || true

# Backup scripts
mkdir -p "$BACKUP_DIR/scripts"
cp ~/*blackroad*.sh "$BACKUP_DIR/scripts/" 2>/dev/null || true
cp ~/enhance-*.sh "$BACKUP_DIR/scripts/" 2>/dev/null || true
cp ~/push-*.sh "$BACKUP_DIR/scripts/" 2>/dev/null || true
cp ~/deploy-*.sh "$BACKUP_DIR/scripts/" 2>/dev/null || true

# Create archive
ARCHIVE="${BACKUP_DIR}.tar.gz"
tar czf "$ARCHIVE" "$BACKUP_DIR"

echo "✅ Backup created: $ARCHIVE"
echo ""
echo "📁 Upload to Google Drive:"
echo "   blackroad.systems@gmail.com: BlackRoad-Backups/"
echo "   amundsonalexa@gmail.com: BlackRoad-Backups/"
echo ""
echo "To automate with rclone:"
echo "   rclone copy \"$ARCHIVE\" gdrive:BlackRoad-Backups/"

# Cleanup
rm -rf "$BACKUP_DIR"

echo ""
echo "💾 Backup ready for upload!"
