#!/bin/bash
# BlackRoad Traffic Light System for Migrations
# Red (🔴): Blocked/Issues | Yellow (🟡): Needs Review | Green (🟢): Ready to Migrate

TRAFFIC_DB="$HOME/.blackroad-traffic-light.db"

init() {
    sqlite3 "$TRAFFIC_DB" <<EOF
CREATE TABLE IF NOT EXISTS migrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_name TEXT UNIQUE NOT NULL,
    status TEXT CHECK(status IN ('red', 'yellow', 'green')) NOT NULL,
    reason TEXT,
    source_org TEXT DEFAULT 'blackboxprogramming',
    target_org TEXT DEFAULT 'BlackRoad-OS',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_status ON migrations(status);
CREATE INDEX IF NOT EXISTS idx_repo ON migrations(repo_name);
EOF
    echo "🚦 Traffic light system initialized: $TRAFFIC_DB"
}

set_light() {
    local repo="$1"
    local status="$2"
    local reason="$3"

    sqlite3 "$TRAFFIC_DB" <<EOF
INSERT INTO migrations (repo_name, status, reason)
VALUES ('$repo', '$status', '$reason')
ON CONFLICT(repo_name) DO UPDATE SET
    status='$status',
    reason='$reason',
    updated_at=CURRENT_TIMESTAMP;
EOF

    local emoji="🔴"
    [[ "$status" == "yellow" ]] && emoji="🟡"
    [[ "$status" == "green" ]] && emoji="🟢"

    echo "$emoji $repo set to $status: $reason"
}

list() {
    local filter="${1:-all}"

    if [[ "$filter" == "all" ]]; then
        sqlite3 -line "$TRAFFIC_DB" "SELECT * FROM migrations ORDER BY status, repo_name;"
    else
        sqlite3 -line "$TRAFFIC_DB" "SELECT * FROM migrations WHERE status='$filter' ORDER BY repo_name;"
    fi
}

stats() {
    echo "🚦 Migration Traffic Light Stats"
    echo "================================"
    sqlite3 "$TRAFFIC_DB" <<EOF
SELECT
    '🟢 GREEN: ' || COUNT(*) || ' repos ready'
FROM migrations WHERE status='green'
UNION ALL
SELECT
    '🟡 YELLOW: ' || COUNT(*) || ' repos need review'
FROM migrations WHERE status='yellow'
UNION ALL
SELECT
    '🔴 RED: ' || COUNT(*) || ' repos blocked'
FROM migrations WHERE status='red';
EOF
}

greenlight() {
    echo "🟢 Repos ready to migrate:"
    sqlite3 "$TRAFFIC_DB" "SELECT repo_name FROM migrations WHERE status='green' ORDER BY repo_name;" | while read repo; do
        echo "  ✓ $repo"
    done
}

case "$1" in
    init) init ;;
    set) set_light "$2" "$3" "$4" ;;
    list) list "$2" ;;
    stats) stats ;;
    greenlight) greenlight ;;
    *)
        echo "Usage: $0 {init|set|list|stats|greenlight}"
        echo "  init                          - Initialize traffic light database"
        echo "  set <repo> <status> <reason>  - Set repo status (red/yellow/green)"
        echo "  list [status]                 - List all or filtered repos"
        echo "  stats                         - Show migration statistics"
        echo "  greenlight                    - Show all green repos ready to migrate"
        ;;
esac
