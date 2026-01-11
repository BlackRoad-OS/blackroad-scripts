#!/bin/bash
# 🔄 Daily Automation Tasks

LOG_DIR=~/blackroad-automation-logs
mkdir -p $LOG_DIR
TIMESTAMP=$(date +%Y%m%d)

# Run monitoring
~/blackroad-unified-monitor.sh > $LOG_DIR/monitor-$TIMESTAMP.log 2>&1

# Update memory system
~/memory-system.sh log automated "Daily Automation" "Ran daily automation tasks" "automation" \
  >> $LOG_DIR/daily-$TIMESTAMP.log 2>&1

# Cleanup old logs (keep 30 days)
find $LOG_DIR -name "*.log" -mtime +30 -delete

echo "✅ Daily automation complete: $(date)"
