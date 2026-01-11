#!/bin/bash
# [TIMELINE] - BlackRoad Universal Timeline
# Single unified timeline of ALL activity
# Version: 1.0.0

set -e

TIMELINE_DIR="$HOME/.blackroad/timeline"
TIMELINE_DB="$TIMELINE_DIR/events.db"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize timeline
init_timeline() {
    echo -e "${BLUE}[TIMELINE]${NC} Initializing universal timeline..."

    mkdir -p "$TIMELINE_DIR"

    # Create database for timeline events
    sqlite3 "$TIMELINE_DB" <<EOF
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    event_type TEXT NOT NULL,
    source TEXT NOT NULL,
    actor TEXT,
    resource TEXT,
    action TEXT NOT NULL,
    details TEXT,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS event_tags (
    event_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    FOREIGN KEY (event_id) REFERENCES events(id)
);

CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_source ON events(source);
CREATE INDEX IF NOT EXISTS idx_events_actor ON events(actor);
CREATE INDEX IF NOT EXISTS idx_tags_tag ON event_tags(tag);
EOF

    echo -e "${GREEN}[TIMELINE]${NC} Timeline initialized at: $TIMELINE_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "timeline" "Initialized [TIMELINE] universal timeline system" "coordination,timeline" 2>/dev/null || true
    fi
}

# Add event to timeline
add_event() {
    local event_type="$1"
    local source="$2"
    local actor="$3"
    local resource="$4"
    local action="$5"
    local details="$6"
    local tags="${7:-}"

    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

    # Insert event
    sqlite3 "$TIMELINE_DB" <<EOF
INSERT INTO events (timestamp, event_type, source, actor, resource, action, details)
VALUES (
    '${timestamp}',
    '${event_type}',
    '${source}',
    '${actor}',
    '${resource}',
    '${action}',
    '${details}'
);
EOF

    local event_id=$(sqlite3 "$TIMELINE_DB" "SELECT last_insert_rowid();")

    # Add tags
    if [ -n "$tags" ]; then
        for tag in $(echo "$tags" | tr ',' ' '); do
            sqlite3 "$TIMELINE_DB" "INSERT INTO event_tags (event_id, tag) VALUES (${event_id}, '${tag}');"
        done
    fi

    echo -e "${GREEN}[TIMELINE]${NC} Event logged (ID: $event_id)"
}

# Import from memory journal
import_memory() {
    echo -e "${BLUE}[TIMELINE]${NC} Importing from memory journal..."

    local journal="$HOME/.blackroad/memory/journals/master-journal.jsonl"

    if [ ! -f "$journal" ]; then
        echo -e "${RED}[TIMELINE]${NC} Memory journal not found"
        return 1
    fi

    local count=0

    # Read recent entries (last 100)
    tail -100 "$journal" | while IFS= read -r line; do
        local timestamp=$(echo "$line" | jq -r '.timestamp')
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')
        local details=$(echo "$line" | jq -r '.details')

        # Insert into timeline
        sqlite3 "$TIMELINE_DB" <<EOF 2>/dev/null
INSERT OR IGNORE INTO events (timestamp, event_type, source, actor, resource, action, details)
VALUES (
    '${timestamp}',
    'memory',
    'memory-journal',
    'system',
    '${entity}',
    '${action}',
    '${details}'
);
EOF

        ((count++))
    done

    echo -e "${GREEN}[TIMELINE]${NC} Imported $count events from memory"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "timeline-import" "Imported $count memory events into timeline" "coordination,timeline,import" 2>/dev/null || true
    fi
}

# Import git commits
import_git() {
    echo -e "${BLUE}[TIMELINE]${NC} Importing git commits..."

    local projects_dir="$HOME/projects"

    if [ ! -d "$projects_dir" ]; then
        echo -e "${YELLOW}[TIMELINE]${NC} Projects directory not found"
        return 0
    fi

    local total_commits=0

    # Find git repos and import recent commits
    find "$projects_dir" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
        local repo_path=$(dirname "$git_dir")
        local repo_name=$(basename "$repo_path")

        # Get last 10 commits
        cd "$repo_path"
        git log -10 --format="%aI|%an|%s" 2>/dev/null | while IFS='|' read -r timestamp author message; do
            sqlite3 "$TIMELINE_DB" <<EOF 2>/dev/null
INSERT OR IGNORE INTO events (timestamp, event_type, source, actor, resource, action, details)
VALUES (
    '${timestamp}',
    'git-commit',
    '${repo_name}',
    '${author}',
    '${repo_name}',
    'commit',
    '${message}'
);
EOF

            ((total_commits++))
        done
    done

    echo -e "${GREEN}[TIMELINE]${NC} Imported $total_commits git commits"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "timeline-git" "Imported $total_commits git commits into timeline" "coordination,timeline,git" 2>/dev/null || true
    fi
}

# Show recent activity
show_recent() {
    local timeframe="${1:-24h}"

    echo -e "${BLUE}[TIMELINE]${NC} Recent activity (${timeframe}):"
    echo ""

    local time_filter=""
    case "$timeframe" in
        1h|hour)
            time_filter="WHERE timestamp >= datetime('now', '-1 hour')"
            ;;
        6h|6hours)
            time_filter="WHERE timestamp >= datetime('now', '-6 hours')"
            ;;
        24h|day|today)
            time_filter="WHERE timestamp >= datetime('now', '-1 day')"
            ;;
        week)
            time_filter="WHERE timestamp >= datetime('now', '-7 days')"
            ;;
        month)
            time_filter="WHERE timestamp >= datetime('now', '-30 days')"
            ;;
        *)
            time_filter=""
            ;;
    esac

    sqlite3 -column -header "$TIMELINE_DB" <<EOF
SELECT
    substr(timestamp, 1, 16) as when,
    event_type as type,
    substr(actor, 1, 20) as who,
    action,
    substr(details, 1, 40) as what
FROM events
$time_filter
ORDER BY timestamp DESC
LIMIT 50;
EOF

    local total=$(sqlite3 "$TIMELINE_DB" "SELECT COUNT(*) FROM events $time_filter;")
    echo ""
    echo -e "${CYAN}Total events in ${timeframe}:${NC} $total"
}

# Filter by type
filter_by_type() {
    local event_type="$1"

    echo -e "${BLUE}[TIMELINE]${NC} Events of type: ${event_type}"
    echo ""

    sqlite3 -column -header "$TIMELINE_DB" <<EOF
SELECT
    substr(timestamp, 1, 16) as when,
    source,
    actor,
    action,
    substr(details, 1, 50) as details
FROM events
WHERE event_type='${event_type}'
ORDER BY timestamp DESC
LIMIT 50;
EOF
}

# Search timeline
search_timeline() {
    local query="$1"

    if [ -z "$query" ]; then
        echo -e "${RED}[TIMELINE]${NC} Search query required"
        return 1
    fi

    echo -e "${BLUE}[TIMELINE]${NC} Searching for: \"${query}\""
    echo ""

    sqlite3 -column -header "$TIMELINE_DB" <<EOF
SELECT
    substr(timestamp, 1, 16) as when,
    event_type as type,
    source,
    action,
    substr(details, 1, 40) as what
FROM events
WHERE details LIKE '%${query}%'
   OR resource LIKE '%${query}%'
   OR action LIKE '%${query}%'
ORDER BY timestamp DESC
LIMIT 30;
EOF

    local total=$(sqlite3 "$TIMELINE_DB" "SELECT COUNT(*) FROM events WHERE details LIKE '%${query}%' OR resource LIKE '%${query}%';")
    echo ""
    echo -e "${CYAN}Total matches:${NC} $total"
}

# Export timeline
export_timeline() {
    local start_date="${1:-}"
    local end_date="${2:-}"
    local output_file="${3:-timeline-export.json}"

    echo -e "${BLUE}[TIMELINE]${NC} Exporting timeline..."

    local date_filter=""
    if [ -n "$start_date" ]; then
        date_filter="WHERE timestamp >= '${start_date}'"
        if [ -n "$end_date" ]; then
            date_filter="${date_filter} AND timestamp <= '${end_date}'"
        fi
    fi

    sqlite3 "$TIMELINE_DB" <<EOF > "$output_file"
.mode json
SELECT * FROM events
$date_filter
ORDER BY timestamp;
EOF

    local event_count=$(wc -l < "$output_file")
    echo -e "${GREEN}[TIMELINE]${NC} Exported $event_count events to: $output_file"
}

# Show statistics
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         ⏱️  TIMELINE STATISTICS ⏱️                     ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_events=$(sqlite3 "$TIMELINE_DB" "SELECT COUNT(*) FROM events;")
    local today=$(sqlite3 "$TIMELINE_DB" "SELECT COUNT(*) FROM events WHERE timestamp >= date('now');")
    local this_week=$(sqlite3 "$TIMELINE_DB" "SELECT COUNT(*) FROM events WHERE timestamp >= datetime('now', '-7 days');")

    echo -e "${GREEN}Total Events:${NC}      $total_events"
    echo -e "${GREEN}Today:${NC}             $today"
    echo -e "${GREEN}This Week:${NC}         $this_week"
    echo ""

    echo -e "${BLUE}Events by Type:${NC}"
    sqlite3 -column -header "$TIMELINE_DB" <<EOF
SELECT
    event_type as type,
    COUNT(*) as count
FROM events
GROUP BY event_type
ORDER BY count DESC;
EOF

    echo ""
    echo -e "${BLUE}Events by Source:${NC}"
    sqlite3 -column -header "$TIMELINE_DB" <<EOF
SELECT
    source,
    COUNT(*) as count
FROM events
GROUP BY source
ORDER BY count DESC
LIMIT 10;
EOF

    echo ""
    echo -e "${BLUE}Most Active Actors:${NC}"
    sqlite3 -column -header "$TIMELINE_DB" <<EOF
SELECT
    actor,
    COUNT(*) as events
FROM events
WHERE actor IS NOT NULL AND actor != 'system'
GROUP BY actor
ORDER BY events DESC
LIMIT 10;
EOF

    echo ""
    echo -e "${BLUE}Activity by Hour (Last 24h):${NC}"
    sqlite3 "$TIMELINE_DB" <<EOF
SELECT
    substr(timestamp, 12, 2) || ':00' as hour,
    COUNT(*) as events
FROM events
WHERE timestamp >= datetime('now', '-1 day')
GROUP BY substr(timestamp, 12, 2)
ORDER BY hour DESC;
EOF
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Universal Timeline [TIMELINE]${NC}

USAGE:
    blackroad-timeline.sh <command> [options]

COMMANDS:
    init                    Initialize timeline
    import-memory           Import from memory journal
    import-git              Import git commits
    recent [timeframe]      Show recent activity
    filter <type>           Filter by event type
    search <query>          Search timeline
    export [start] [end]    Export to JSON
    stats                   Show statistics
    help                    Show this help

TIMEFRAMES:
    1h, 6h, 24h, day, today, week, month, all

EVENT TYPES:
    memory, git-commit, deployment, agent-work, health-check

EXAMPLES:
    # Initialize
    blackroad-timeline.sh init

    # Import data
    blackroad-timeline.sh import-memory
    blackroad-timeline.sh import-git

    # View recent activity
    blackroad-timeline.sh recent 24h
    blackroad-timeline.sh recent week

    # Filter by type
    blackroad-timeline.sh filter git-commit
    blackroad-timeline.sh filter deployment

    # Search
    blackroad-timeline.sh search "authentication"
    blackroad-timeline.sh search "cloudflare"

    # Export
    blackroad-timeline.sh export 2026-01-01 2026-01-07 jan-week1.json

    # Statistics
    blackroad-timeline.sh stats

DATABASE: $TIMELINE_DB
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_timeline
            ;;
        import-memory)
            import_memory
            ;;
        import-git)
            import_git
            ;;
        recent)
            show_recent "${2:-24h}"
            ;;
        filter)
            if [ -z "$2" ]; then
                echo -e "${RED}[TIMELINE]${NC} Event type required"
                exit 1
            fi
            filter_by_type "$2"
            ;;
        search)
            search_timeline "$2"
            ;;
        export)
            export_timeline "$2" "$3" "${4:-timeline-export.json}"
            ;;
        stats)
            show_stats
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[TIMELINE]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
