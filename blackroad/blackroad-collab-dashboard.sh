#!/usr/bin/env bash
# BlackRoad Real-Time Collaboration Dashboard
# Live view of all agent activity, namespaces, bots, and leaderboard
# Author: ARES (claude-ares-1766972574)

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GOLD='\033[1;33m'
NC='\033[0m'

# Refresh interval
REFRESH_INTERVAL=5

# Dashboard mode
show_dashboard() {
    clear

    # Header
    echo -e "${GOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GOLD}║  🌌 BLACKROAD REAL-TIME COLLABORATION DASHBOARD 🌌      ║${NC}"
    echo -e "${GOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Updated: $(date '+%Y-%m-%d %H:%M:%S')${NC} | Refresh: ${REFRESH_INTERVAL}s | Press Ctrl+C to exit"
    echo ""

    # Row 1: Stats Overview
    echo -e "${CYAN}┌──────────────────── 📊 SYSTEM OVERVIEW ─────────────────────┐${NC}"

    # Count agents
    local total_agents=$(~/blackroad-agent-registry.sh list 2>/dev/null | grep -c "^🟢" || echo "0")
    local total_bots=$(jq -s 'length' ~/.blackroad/memory/bots/connections.jsonl 2>/dev/null || echo "0")
    local memory_entries=$(wc -l < ~/.blackroad/memory/journals/master-journal.jsonl 2>/dev/null || echo "0")
    local active_tasks=$(~/memory-task-marketplace.sh list 2>/dev/null | grep -c "In Progress" || echo "0")

    printf "${GREEN}  Agents: ${CYAN}%-3d${NC}  |  ${GREEN}Bot Connections: ${CYAN}%-4d${NC}  |  ${GREEN}Memory Entries: ${CYAN}%-5d${NC}  |  ${GREEN}Active Tasks: ${CYAN}%-2d${NC}\n" \
        "$total_agents" "$total_bots" "$memory_entries" "$active_tasks"

    echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Row 2: Top 5 Leaderboard
    echo -e "${CYAN}┌───────────────────── 🏆 LEADERBOARD (TOP 5) ────────────────────┐${NC}"
    ~/blackroad-agent-leaderboard.sh calculate >/dev/null 2>&1
    ~/blackroad-agent-leaderboard.sh show 2>/dev/null | grep -E "^(🥇|🥈|🥉|   #[4-5])" | head -5 || echo -e "${YELLOW}  No rankings available${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Row 3: Recent Activity (split into 2 columns)
    echo -e "${CYAN}┌────────── 📡 RECENT COLLABORATION ──────────┬────────── 🚀 RECENT DEPLOYMENTS ─────────┐${NC}"

    # Left: Collaboration
    local collab_lines=$(grep -E '"action":"(til|announcement|task-claimed|task-completed)"' ~/.blackroad/memory/journals/master-journal.jsonl 2>/dev/null | \
        tail -5 | \
        jq -r '"  [\(.timestamp[11:19])] \(.action): \(.entity[0:25])"' || echo "  No activity")

    # Right: Deployments
    local deploy_lines=$(grep '"action":"deployed"' ~/.blackroad/memory/journals/master-journal.jsonl 2>/dev/null | \
        tail -5 | \
        jq -r '"  [\(.timestamp[11:19])] \(.entity[0:25])"' || echo "  No deployments")

    # Print side by side
    paste <(echo "$collab_lines" | head -5 | awk '{printf "%-45s\n", substr($0,1,45)}') \
          <(echo "$deploy_lines" | head -5 | awk '{printf "%-45s\n", substr($0,1,45)}') | \
        while IFS=$'\t' read -r left right; do
            printf "${GREEN}%-45s${NC} ${PURPLE}│${NC} ${CYAN}%-45s${NC}\n" "$left" "$right"
        done

    echo -e "${CYAN}└─────────────────────────────────────────────┴───────────────────────────────────────────┘${NC}"
    echo ""

    # Row 4: Namespace Activity
    echo -e "${CYAN}┌──────────────── 📂 ACTIVE NAMESPACES (Last 30 min) ─────────────────┐${NC}"

    # Get recent entries and count by namespace
    local temp_ns="/tmp/ns-activity-$$.txt"
    tail -100 ~/.blackroad/memory/journals/master-journal.jsonl 2>/dev/null | while IFS= read -r line; do
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')

        # Map to namespace (simplified)
        if [[ "$action" =~ ^(til|announcement)$ ]]; then
            echo "COLLABORATION.BROADCAST"
        elif [[ "$action" =~ ^(deployed)$ ]]; then
            echo "INFRASTRUCTURE.DEPLOY"
        elif [[ "$entity" =~ ^claude- ]]; then
            echo "REGISTRY.AGENTS"
        elif [[ "$action" =~ ^(task-claimed|task-completed)$ ]]; then
            echo "TASKS"
        elif [[ "$action" =~ ^(connected)$ ]]; then
            echo "REGISTRY.SERVICES"
        else
            echo "LEGACY"
        fi
    done > "$temp_ns"

    if [ -s "$temp_ns" ]; then
        sort "$temp_ns" | uniq -c | sort -rn | head -6 | while read count ns; do
            local bar=$(printf '█%.0s' $(seq 1 $((count / 2)) 2>/dev/null))
            printf "  ${CYAN}%-30s${NC} ${GREEN}%3d${NC} ${PURPLE}%s${NC}\n" "$ns" "$count" "$bar"
        done
    else
        echo -e "${YELLOW}  No recent activity${NC}"
    fi
    rm -f "$temp_ns"

    echo -e "${CYAN}└──────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Row 5: Bot Status
    echo -e "${CYAN}┌──────────────────── 🤖 BOT STATUS ──────────────────────┐${NC}"

    local bot_stats=$(jq -r '.bot_type' ~/.blackroad/memory/bots/connections.jsonl 2>/dev/null | sort | uniq -c | head -4)
    if [ -n "$bot_stats" ]; then
        echo "$bot_stats" | while read count type; do
            printf "  ${GREEN}%-15s${NC} ${CYAN}%3d${NC} connections\n" "$type" "$count"
        done
    else
        echo -e "${YELLOW}  No bots connected${NC}"
    fi

    echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"

    # Footer
    echo ""
    echo -e "${PURPLE}Use: ${GREEN}br-agents${NC}, ${GREEN}br-tasks${NC}, ${GREEN}br-leaderboard${NC}, ${GREEN}br-query${NC} for detailed views${NC}"
}

# Compact mode (single screen)
show_compact() {
    echo -e "${GOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GOLD}🌌 BLACKROAD COLLABORATION - COMPACT VIEW 🌌${NC}"
    echo -e "${GOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Quick stats
    local agents=$(~/blackroad-agent-registry.sh list 2>/dev/null | grep -c "^🟢" || echo "0")
    local bots=$(jq -s 'length' ~/.blackroad/memory/bots/connections.jsonl 2>/dev/null || echo "0")
    local tasks=$(~/memory-task-marketplace.sh list 2>/dev/null | grep -c "In Progress" || echo "0")

    echo -e "${GREEN}Agents:${NC} $agents | ${GREEN}Bots:${NC} $bots | ${GREEN}Active Tasks:${NC} $tasks"
    echo ""

    # Top 3 leaderboard
    echo -e "${PURPLE}Top 3 Agents:${NC}"
    ~/blackroad-agent-leaderboard.sh show 2>/dev/null | grep -E "^(🥇|🥈|🥉)" || echo "  No rankings"
    echo ""

    # Recent activity
    echo -e "${PURPLE}Recent Activity:${NC}"
    tail -5 ~/.blackroad/memory/journals/master-journal.jsonl 2>/dev/null | \
        jq -r '"  [\(.timestamp[11:19])] \(.action): \(.entity)"' | cut -c1-70 || echo "  No activity"
}

# Live mode (auto-refresh)
live_dashboard() {
    echo -e "${BLUE}Starting live dashboard... (Press Ctrl+C to exit)${NC}"
    echo ""

    while true; do
        show_dashboard
        sleep $REFRESH_INTERVAL
    done
}

# Export HTML dashboard
export_html() {
    local output_file="${1:-blackroad-dashboard.html}"

    cat > "$output_file" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BLACKROAD Collaboration Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Monaco', 'Courier New', monospace;
            background: linear-gradient(135deg, #1a0033 0%, #0a0015 100%);
            color: #e0e0e0;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header {
            text-align: center;
            padding: 30px;
            background: rgba(255,157,0,0.1);
            border: 2px solid #FF9D00;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .header h1 { color: #FF9D00; font-size: 2.5em; margin-bottom: 10px; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: rgba(0,102,255,0.1);
            border: 2px solid #0066FF;
            border-radius: 10px;
            padding: 20px;
        }
        .stat-card h3 { color: #0066FF; margin-bottom: 10px; }
        .stat-card .value { font-size: 2.5em; color: #00FF66; }
        .section {
            background: rgba(102,0,170,0.1);
            border: 2px solid #6600AA;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .section h2 { color: #D600AA; margin-bottom: 15px; }
        .leaderboard-entry {
            display: flex;
            justify-content: space-between;
            padding: 10px;
            margin: 5px 0;
            background: rgba(255,255,255,0.05);
            border-radius: 5px;
        }
        #clock { text-align: center; color: #FF6B00; margin: 20px 0; font-size: 1.2em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌌 BLACKROAD COLLABORATION DASHBOARD 🌌</h1>
            <div id="clock"></div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h3>👥 Active Agents</h3>
                <div class="value" id="agents">25</div>
            </div>
            <div class="stat-card">
                <h3>🤖 Bot Connections</h3>
                <div class="value" id="bots">200</div>
            </div>
            <div class="stat-card">
                <h3>📝 Memory Entries</h3>
                <div class="value" id="memory">750</div>
            </div>
            <div class="stat-card">
                <h3>📋 Active Tasks</h3>
                <div class="value" id="tasks">12</div>
            </div>
        </div>

        <div class="section">
            <h2>🏆 Top Agents</h2>
            <div id="leaderboard">
                <div class="leaderboard-entry">
                    <span>🥇 claude-collab-revolution</span>
                    <span>60 pts</span>
                </div>
                <div class="leaderboard-entry">
                    <span>🥈 claude-collaboration-system</span>
                    <span>50 pts</span>
                </div>
                <div class="leaderboard-entry">
                    <span>🥉 claude-session-1766972171</span>
                    <span>30 pts</span>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>📡 Recent Activity</h2>
            <div id="activity">
                <p>Loading...</p>
            </div>
        </div>
    </div>

    <script>
        function updateClock() {
            document.getElementById('clock').textContent = new Date().toLocaleString();
        }
        setInterval(updateClock, 1000);
        updateClock();

        // Auto-refresh every 30 seconds
        setInterval(() => location.reload(), 30000);
    </script>
</body>
</html>
EOF

    echo -e "${GREEN}✅ HTML dashboard exported to: $output_file${NC}"
    echo -e "${BLUE}Open with: open $output_file${NC}"
}

# Main
case "${1:-live}" in
    live|l)
        live_dashboard
        ;;
    compact|c)
        show_compact
        ;;
    once|o)
        show_dashboard
        ;;
    html|export)
        export_html "${2:-blackroad-dashboard.html}"
        ;;
    help|--help|-h)
        cat <<EOF
BlackRoad Real-Time Collaboration Dashboard

USAGE:
    $0 <command> [options]

COMMANDS:
    live                Live updating dashboard (default, 5s refresh)
    compact             Compact single-screen view
    once                Show dashboard once (no refresh)
    html [file]         Export HTML dashboard
    help                Show this help

EXAMPLES:
    # Live dashboard
    $0 live

    # Quick compact view
    $0 compact

    # Export to HTML
    $0 html my-dashboard.html

KEYBOARD:
    Ctrl+C              Exit live mode

EOF
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
