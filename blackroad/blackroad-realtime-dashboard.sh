#!/bin/bash
# BlackRoad Real-Time Collaboration Dashboard
# Shows what ALL Claude instances are doing RIGHT NOW
# Version: 1.0.0

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Clear screen
clear_screen() {
    clear
}

# Get active Claude agents
get_active_agents() {
    if [ -f ~/.blackroad/router/agents.db ]; then
        sqlite3 ~/.blackroad/router/agents.db "
            SELECT COUNT(*) FROM agents WHERE status='available' OR status='busy';
        " 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get active work claims
get_active_claims() {
    if [ -f ~/.blackroad/conflict/locks.db ]; then
        sqlite3 ~/.blackroad/conflict/locks.db "
            SELECT COUNT(*) FROM work_claims WHERE status='active';
        " 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get pending tasks
get_pending_tasks() {
    if [ -f ~/.blackroad/router/agents.db ]; then
        sqlite3 ~/.blackroad/router/agents.db "
            SELECT COUNT(*) FROM tasks WHERE status='pending';
        " 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get recent memory activity
get_recent_activity() {
    if [ -f ~/.blackroad/memory/journals/master-journal.jsonl ]; then
        tail -5 ~/.blackroad/memory/journals/master-journal.jsonl | \
        jq -r '[.timestamp[11:19], .action, .entity] | @tsv' 2>/dev/null | \
        awk -F'\t' '{printf "  %s  %s → %s\n", $1, $2, $3}'
    else
        echo "  No recent activity"
    fi
}

# Get infrastructure health
get_health_status() {
    if [ -f ~/.blackroad/health/metrics.db ]; then
        local total=$(sqlite3 ~/.blackroad/health/metrics.db "
            SELECT COUNT(*) FROM uptime_stats;
        " 2>/dev/null || echo "0")

        local healthy=$(sqlite3 ~/.blackroad/health/metrics.db "
            SELECT COUNT(*) FROM uptime_stats WHERE last_status='healthy';
        " 2>/dev/null || echo "0")

        if [ "$total" -eq 0 ]; then
            echo "Unknown"
        else
            local pct=$((healthy * 100 / total))
            echo "${pct}%"
        fi
    else
        echo "Unknown"
    fi
}

# Show main dashboard
show_dashboard() {
    clear_screen

    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                                   ║${NC}"
    echo -e "${BOLD}${CYAN}║     🌌 BLACKROAD REAL-TIME COLLABORATION DASHBOARD 🌌            ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                                   ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # System Status
    echo -e "${BOLD}${PURPLE}━━━ SYSTEM STATUS ━━━${NC}"
    echo ""

    local active_agents=$(get_active_agents)
    local active_claims=$(get_active_claims)
    local pending_tasks=$(get_pending_tasks)
    local health=$(get_health_status)

    echo -e "  ${GREEN}●${NC} Active Claude Agents:     ${BOLD}$active_agents${NC}"
    echo -e "  ${YELLOW}●${NC} Active Work Claims:       ${BOLD}$active_claims${NC}"
    echo -e "  ${BLUE}●${NC} Pending Tasks:            ${BOLD}$pending_tasks${NC}"
    echo -e "  ${PURPLE}●${NC} Infrastructure Health:    ${BOLD}$health${NC}"
    echo ""

    # Active Agents
    echo -e "${BOLD}${PURPLE}━━━ ACTIVE CLAUDE AGENTS ━━━${NC}"
    echo ""

    if [ -f ~/.blackroad/router/agents.db ]; then
        sqlite3 -column ~/.blackroad/router/agents.db "
            SELECT
                substr(id, 1, 35) as agent,
                status,
                current_workload as work,
                total_tasks_completed as done
            FROM agents
            WHERE status IN ('available', 'busy')
            ORDER BY last_active DESC
            LIMIT 10;
        " 2>/dev/null | while read -r line; do
            if echo "$line" | grep -q "busy"; then
                echo -e "${YELLOW}  ⚙${NC}  $line"
            else
                echo -e "${GREEN}  ✓${NC}  $line"
            fi
        done || echo -e "  ${YELLOW}No active agents${NC}"
    else
        echo -e "  ${YELLOW}Router not initialized${NC}"
    fi

    echo ""

    # Active Work
    echo -e "${BOLD}${PURPLE}━━━ ACTIVE WORK (Right Now) ━━━${NC}"
    echo ""

    if [ -f ~/.blackroad/conflict/locks.db ]; then
        local claims=$(sqlite3 ~/.blackroad/conflict/locks.db "
            SELECT COUNT(*) FROM work_claims WHERE status='active';
        " 2>/dev/null || echo "0")

        if [ "$claims" -eq 0 ]; then
            echo -e "  ${GREEN}✓${NC} No active work claims - All resources available!"
        else
            sqlite3 -column ~/.blackroad/conflict/locks.db "
                SELECT
                    substr(agent_id, 1, 30) as agent,
                    substr(resource, 1, 25) as working_on,
                    substr(claimed_at, 12, 5) as since
                FROM work_claims
                WHERE status='active'
                ORDER BY claimed_at DESC
                LIMIT 8;
            " 2>/dev/null | sed 's/^/  ⚙  /'
        fi
    else
        echo -e "  ${YELLOW}Conflict detector not initialized${NC}"
    fi

    echo ""

    # Recent Activity
    echo -e "${BOLD}${PURPLE}━━━ RECENT ACTIVITY (Last 5 actions) ━━━${NC}"
    echo ""
    get_recent_activity

    echo ""

    # System Health
    echo -e "${BOLD}${PURPLE}━━━ INFRASTRUCTURE HEALTH ━━━${NC}"
    echo ""

    if [ -f ~/.blackroad/health/metrics.db ]; then
        sqlite3 ~/.blackroad/health/metrics.db "
            SELECT
                system,
                last_status,
                CAST(100.0 * successful_checks / NULLIF(total_checks, 0) AS INT) || '%' as uptime
            FROM uptime_stats
            ORDER BY system;
        " 2>/dev/null | while IFS='|' read -r system status uptime; do
            if [ "$status" = "healthy" ]; then
                echo -e "  ${GREEN}●${NC} $system: $status ($uptime uptime)"
            elif [ "$status" = "degraded" ]; then
                echo -e "  ${YELLOW}●${NC} $system: $status ($uptime uptime)"
            else
                echo -e "  ${RED}●${NC} $system: $status ($uptime uptime)"
            fi
        done || echo -e "  ${YELLOW}No health data${NC}"
    else
        echo -e "  ${YELLOW}Health monitor not initialized${NC}"
    fi

    echo ""

    # Quick Stats
    echo -e "${BOLD}${PURPLE}━━━ QUICK STATS ━━━${NC}"
    echo ""

    # Total indexed assets
    if [ -f ~/.blackroad/index/assets.db ]; then
        local total_assets=$(sqlite3 ~/.blackroad/index/assets.db "SELECT COUNT(*) FROM assets;" 2>/dev/null || echo "0")
        echo -e "  📦 Total Assets Indexed:    ${BOLD}$total_assets${NC}"
    fi

    # Knowledge graph
    if [ -f ~/.blackroad/graph/knowledge.db ]; then
        local nodes=$(sqlite3 ~/.blackroad/graph/knowledge.db "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
        local edges=$(sqlite3 ~/.blackroad/graph/knowledge.db "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")
        echo -e "  🕸️  Knowledge Graph:         ${BOLD}$nodes nodes, $edges edges${NC}"
    fi

    # Memory entries
    if [ -f ~/.blackroad/memory/journals/master-journal.jsonl ]; then
        local entries=$(wc -l < ~/.blackroad/memory/journals/master-journal.jsonl)
        echo -e "  📝 Memory Entries:          ${BOLD}$entries${NC}"
    fi

    # Timeline events
    if [ -f ~/.blackroad/timeline/events.db ]; then
        local events=$(sqlite3 ~/.blackroad/timeline/events.db "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")
        echo -e "  ⏱️  Timeline Events:         ${BOLD}$events${NC}"
    fi

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit | Refreshing every 5 seconds...${NC}"
    echo ""
}

# Show compact dashboard
show_compact() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🌌 BLACKROAD COLLABORATION - COMPACT VIEW 🌌   ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""

    local agents=$(get_active_agents)
    local claims=$(get_active_claims)
    local tasks=$(get_pending_tasks)
    local health=$(get_health_status)

    echo -e "${GREEN}Agents:${NC} $agents  ${YELLOW}Working:${NC} $claims  ${BLUE}Tasks:${NC} $tasks  ${PURPLE}Health:${NC} $health"
    echo ""

    if [ -f ~/.blackroad/conflict/locks.db ]; then
        local active_work=$(sqlite3 ~/.blackroad/conflict/locks.db "
            SELECT substr(agent_id, 1, 20) || ' → ' || substr(resource, 1, 30)
            FROM work_claims
            WHERE status='active'
            LIMIT 5;
        " 2>/dev/null)

        if [ -n "$active_work" ]; then
            echo -e "${YELLOW}Active Work:${NC}"
            echo "$active_work" | sed 's/^/  /'
        fi
    fi
}

# Watch mode (continuous refresh)
watch_mode() {
    echo -e "${CYAN}Starting real-time dashboard...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    sleep 2

    while true; do
        show_dashboard
        sleep 5
    done
}

# Export dashboard data
export_data() {
    local output_file="${1:-dashboard-$(date +%Y%m%d-%H%M%S).json}"

    echo -e "${BLUE}[DASHBOARD]${NC} Exporting dashboard data..."

    cat > "$output_file" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "active_agents": $(get_active_agents),
  "active_claims": $(get_active_claims),
  "pending_tasks": $(get_pending_tasks),
  "health_status": "$(get_health_status)",
  "systems": {
EOF

    # Add system data
    if [ -f ~/.blackroad/index/assets.db ]; then
        local assets=$(sqlite3 ~/.blackroad/index/assets.db "SELECT COUNT(*) FROM assets;" 2>/dev/null || echo "0")
        echo "    \"index_assets\": $assets," >> "$output_file"
    fi

    if [ -f ~/.blackroad/graph/knowledge.db ]; then
        local nodes=$(sqlite3 ~/.blackroad/graph/knowledge.db "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")
        local edges=$(sqlite3 ~/.blackroad/graph/knowledge.db "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")
        echo "    \"graph_nodes\": $nodes," >> "$output_file"
        echo "    \"graph_edges\": $edges," >> "$output_file"
    fi

    if [ -f ~/.blackroad/memory/journals/master-journal.jsonl ]; then
        local entries=$(wc -l < ~/.blackroad/memory/journals/master-journal.jsonl)
        echo "    \"memory_entries\": $entries" >> "$output_file"
    fi

    cat >> "$output_file" <<EOF
  }
}
EOF

    echo -e "${GREEN}[DASHBOARD]${NC} Exported to: $output_file"
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Real-Time Collaboration Dashboard${NC}

Shows what ALL Claude instances are doing RIGHT NOW.

USAGE:
    blackroad-realtime-dashboard.sh <command>

COMMANDS:
    watch           Watch mode (auto-refresh every 5s)
    show            Show dashboard once
    compact         Show compact view
    export [file]   Export data to JSON
    help            Show this help

EXAMPLES:
    # Watch mode (continuous)
    blackroad-realtime-dashboard.sh watch

    # One-time view
    blackroad-realtime-dashboard.sh show

    # Compact view
    blackroad-realtime-dashboard.sh compact

    # Export data
    blackroad-realtime-dashboard.sh export dashboard.json

WHAT IT SHOWS:
    ✓ Active Claude agents
    ✓ Current work (who's working on what)
    ✓ Recent activity
    ✓ Infrastructure health
    ✓ Pending tasks
    ✓ System statistics

TIP: Run in watch mode in a separate terminal!
EOF
}

# Main command handler
main() {
    local cmd="${1:-watch}"

    case "$cmd" in
        watch)
            watch_mode
            ;;
        show)
            show_dashboard
            ;;
        compact)
            show_compact
            ;;
        export)
            export_data "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[DASHBOARD]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
