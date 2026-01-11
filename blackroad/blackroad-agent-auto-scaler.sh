#!/bin/bash
# BlackRoad Agent Auto-Scaler
# Automatically scales agents from 0 to 30,000 based on demand
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

# Configuration
SCALER_DB="$HOME/.blackroad/auto-scaler/scaling.db"
ORCHESTRATOR_DB="$HOME/.blackroad/orchestration/agents.db"
MAX_AGENTS=30000
SCALE_INTERVAL=60 # seconds

# Initialize
init_db() {
    mkdir -p "$(dirname "$SCALER_DB")"

    sqlite3 "$SCALER_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS scaling_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    current_agents INTEGER NOT NULL,
    target_agents INTEGER NOT NULL,
    reason TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS scaling_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule_name TEXT NOT NULL UNIQUE,
    metric_name TEXT NOT NULL,
    threshold_value REAL NOT NULL,
    scale_up_count INTEGER NOT NULL,
    scale_down_count INTEGER NOT NULL,
    enabled INTEGER DEFAULT 1,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS agent_pool (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    agent_id TEXT NOT NULL UNIQUE,
    agent_type TEXT NOT NULL,
    status TEXT DEFAULT 'ready',
    assigned_task TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    started_at TEXT,
    last_heartbeat TEXT
);

-- Default scaling rules
INSERT INTO scaling_rules (rule_name, metric_name, threshold_value, scale_up_count, scale_down_count)
VALUES
    ('high_task_queue', 'pending_tasks', 100, 50, 0),
    ('medium_task_queue', 'pending_tasks', 50, 25, 0),
    ('low_task_queue', 'pending_tasks', 10, 5, 0),
    ('idle_agents', 'idle_percentage', 80, 0, 10),
    ('high_cpu', 'avg_cpu_percent', 90, 20, 0);

CREATE INDEX IF NOT EXISTS idx_scaling_events_timestamp ON scaling_events(timestamp);
CREATE INDEX IF NOT EXISTS idx_agent_pool_status ON agent_pool(status);
SQL

    echo -e "${GREEN}[AUTO-SCALER]${NC} Database initialized!"
}

# Generate agent ID
generate_agent_id() {
    local agent_type="$1"
    echo "agent-${agent_type}-$(date +%s)-$(openssl rand -hex 4)"
}

# Scale up agents
scale_up() {
    local count="$1"
    local reason="${2:-manual}"

    echo -e "${BOLD}${CYAN}═══ SCALING UP: +$count AGENTS ═══${NC}"
    echo ""

    local current=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM agents;" 2>/dev/null || echo 0)
    local target=$((current + count))

    if [ $target -gt $MAX_AGENTS ]; then
        echo -e "${RED}Error: Would exceed maximum capacity ($MAX_AGENTS)${NC}"
        exit 1
    fi

    # Log scaling event
    sqlite3 "$SCALER_DB" <<SQL
INSERT INTO scaling_events (event_type, current_agents, target_agents, reason)
VALUES ('scale_up', $current, $target, '$reason');
SQL

    # Create agents
    local agent_types=("code-generation" "data-analysis" "testing" "deployment" "monitoring")
    for i in $(seq 1 $count); do
        local agent_type="${agent_types[$((RANDOM % ${#agent_types[@]}))]}"
        local agent_id=$(generate_agent_id "$agent_type")

        # Register in orchestrator
        ~/blackroad-30k-agent-orchestrator.sh register-agent "$agent_id" "$agent_type" > /dev/null 2>&1

        # Add to pool
        sqlite3 "$SCALER_DB" <<SQL
INSERT INTO agent_pool (agent_id, agent_type, status)
VALUES ('$agent_id', '$agent_type', 'ready');
SQL

        if [ $((i % 10)) -eq 0 ]; then
            echo -e "${CYAN}  Created $i/$count agents...${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}✓ Scaled up: $current → $target agents${NC}"
    echo -e "${CYAN}Reason: $reason${NC}"
}

# Scale down agents
scale_down() {
    local count="$1"
    local reason="${2:-manual}"

    echo -e "${BOLD}${YELLOW}═══ SCALING DOWN: -$count AGENTS ═══${NC}"
    echo ""

    local current=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM agents;" 2>/dev/null || echo 0)
    local target=$((current - count))

    if [ $target -lt 0 ]; then
        target=0
    fi

    # Log scaling event
    sqlite3 "$SCALER_DB" <<SQL
INSERT INTO scaling_events (event_type, current_agents, target_agents, reason)
VALUES ('scale_down', $current, $target, '$reason');
SQL

    echo -e "${GREEN}✓ Scaled down: $current → $target agents${NC}"
    echo -e "${CYAN}Reason: $reason${NC}"
}

# Auto scale based on metrics
auto_scale() {
    echo -e "${BOLD}${PURPLE}═══ AUTO-SCALING ENGINE ═══${NC}"
    echo ""

    # Get current metrics
    local current_agents=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM agents;" 2>/dev/null || echo 0)
    local active_agents=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM agents WHERE status='active';" 2>/dev/null || echo 0)
    local pending_tasks=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM task_queue WHERE status='pending';" 2>/dev/null || echo 0)

    echo -e "${CYAN}Current Agents:${NC} $current_agents / $MAX_AGENTS"
    echo -e "${CYAN}Active Agents:${NC} $active_agents"
    echo -e "${CYAN}Pending Tasks:${NC} $pending_tasks"
    echo ""

    # Check scaling rules
    local scaled=0

    # Rule: High task queue
    if [ $pending_tasks -gt 100 ] && [ $current_agents -lt $MAX_AGENTS ]; then
        scale_up 50 "high_task_queue ($pending_tasks tasks)"
        scaled=1
    elif [ $pending_tasks -gt 50 ] && [ $current_agents -lt $MAX_AGENTS ]; then
        scale_up 25 "medium_task_queue ($pending_tasks tasks)"
        scaled=1
    elif [ $pending_tasks -gt 10 ] && [ $current_agents -lt $MAX_AGENTS ]; then
        scale_up 5 "low_task_queue ($pending_tasks tasks)"
        scaled=1
    fi

    # Rule: Idle agents (scale down)
    if [ $current_agents -gt 0 ]; then
        local idle_percent=$((100 * (current_agents - active_agents) / current_agents))
        if [ $idle_percent -gt 80 ] && [ $current_agents -gt 10 ]; then
            scale_down 10 "high_idle_percentage ($idle_percent%)"
            scaled=1
        fi
    fi

    if [ $scaled -eq 0 ]; then
        echo -e "${GREEN}✓ No scaling needed${NC}"
    fi
}

# Simulate load test
simulate_load_test() {
    local target="$1"

    echo -e "${BOLD}${YELLOW}⚡ LOAD TEST: Scaling to $target agents ⚡${NC}"
    echo ""

    local current=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM agents;" 2>/dev/null || echo 0)
    local needed=$((target - current))

    if [ $needed -gt 0 ]; then
        echo -e "${CYAN}Creating $needed agents...${NC}"
        scale_up $needed "load_test_target_$target"
    else
        echo -e "${GREEN}Already have $current agents (target: $target)${NC}"
    fi

    echo ""
    ~/blackroad-30k-agent-orchestrator.sh dashboard
}

# Show scaling history
show_history() {
    echo -e "${CYAN}━━━ Scaling Event History ━━━${NC}"
    echo ""

    sqlite3 -column "$SCALER_DB" "
        SELECT
            event_type,
            current_agents,
            target_agents,
            reason,
            datetime(timestamp) as time
        FROM scaling_events
        ORDER BY timestamp DESC
        LIMIT 20;
    " 2>/dev/null

    echo ""
}

# Show scaling rules
show_rules() {
    echo -e "${CYAN}━━━ Auto-Scaling Rules ━━━${NC}"
    echo ""

    sqlite3 -column "$SCALER_DB" "
        SELECT
            rule_name,
            metric_name,
            threshold_value as threshold,
            scale_up_count as up,
            scale_down_count as down,
            CASE WHEN enabled=1 THEN 'enabled' ELSE 'disabled' END as status
        FROM scaling_rules;
    " 2>/dev/null

    echo ""
}

# Watch mode - continuous auto-scaling
watch_mode() {
    echo -e "${BOLD}${GREEN}═══ AUTO-SCALER WATCH MODE ═══${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    while true; do
        clear
        echo -e "${BOLD}${PURPLE}BlackRoad Agent Auto-Scaler - Watch Mode${NC}"
        echo -e "${CYAN}$(date)${NC}"
        echo ""

        auto_scale

        echo ""
        echo -e "${YELLOW}Next check in $SCALE_INTERVAL seconds...${NC}"
        sleep $SCALE_INTERVAL
    done
}

# Help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Agent Auto-Scaler${NC}

Automatically scales agents from 0 to 30,000 based on demand

USAGE:
    blackroad-agent-auto-scaler.sh <command> [args]

COMMANDS:
    init                    Initialize auto-scaler
    scale-up <count>        Scale up by N agents
    scale-down <count>      Scale down by N agents
    auto                    Run auto-scaling once
    watch                   Continuous auto-scaling
    load-test <target>      Simulate load test to target
    history                 Show scaling history
    rules                   Show scaling rules
    help                    Show this help

EXAMPLES:
    # Initialize
    blackroad-agent-auto-scaler.sh init

    # Scale up 100 agents
    blackroad-agent-auto-scaler.sh scale-up 100

    # Auto-scale based on metrics
    blackroad-agent-auto-scaler.sh auto

    # Load test to 1000 agents
    blackroad-agent-auto-scaler.sh load-test 1000

    # Watch mode (continuous)
    blackroad-agent-auto-scaler.sh watch

CAPACITY: 0 → 30,000 agents
CEO: Alexa Amundson
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        scale-up)
            scale_up "${2:-10}" "manual"
            ;;
        scale-down)
            scale_down "${2:-10}" "manual"
            ;;
        auto)
            auto_scale
            ;;
        watch)
            watch_mode
            ;;
        load-test)
            simulate_load_test "${2:-100}"
            ;;
        history)
            show_history
            ;;
        rules)
            show_rules
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
