#!/bin/bash
# BlackRoad Distributed Task Queue System
# Distributes tasks across 30,000 agents intelligently
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
TASK_DB="$HOME/.blackroad/tasks/distributed.db"
ORCHESTRATOR_DB="$HOME/.blackroad/orchestration/agents.db"

# Initialize
init_db() {
    mkdir -p "$(dirname "$TASK_DB")"

    sqlite3 "$TASK_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL UNIQUE,
    task_type TEXT NOT NULL,
    priority TEXT DEFAULT 'medium',
    payload TEXT,
    assigned_agent_id TEXT,
    status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    assigned_at TEXT,
    started_at TEXT,
    completed_at TEXT,
    result TEXT,
    error TEXT
);

CREATE TABLE IF NOT EXISTS task_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type_name TEXT NOT NULL UNIQUE,
    description TEXT,
    estimated_duration_ms INTEGER DEFAULT 1000,
    required_agent_type TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS task_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_type TEXT NOT NULL,
    total_tasks INTEGER DEFAULT 0,
    completed_tasks INTEGER DEFAULT 0,
    failed_tasks INTEGER DEFAULT 0,
    avg_duration_ms REAL DEFAULT 0,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Default task types
INSERT OR IGNORE INTO task_types (type_name, description, estimated_duration_ms, required_agent_type)
VALUES
    ('code-generation', 'Generate code based on specifications', 5000, 'code-generation'),
    ('code-review', 'Review code for quality and security', 3000, 'code-generation'),
    ('data-analysis', 'Analyze datasets and generate insights', 10000, 'data-analysis'),
    ('testing', 'Run automated tests', 2000, 'testing'),
    ('deployment', 'Deploy applications to production', 8000, 'deployment'),
    ('monitoring', 'Monitor system health and metrics', 1000, 'monitoring'),
    ('refactoring', 'Refactor code for better quality', 7000, 'code-generation'),
    ('documentation', 'Generate documentation', 4000, 'code-generation'),
    ('security-scan', 'Scan for security vulnerabilities', 6000, 'testing'),
    ('performance-test', 'Run performance benchmarks', 15000, 'testing');

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority);
CREATE INDEX IF NOT EXISTS idx_tasks_type ON tasks(task_type);
SQL

    echo -e "${GREEN}[TASK-SYSTEM]${NC} Database initialized!"
}

# Create task
create_task() {
    local task_type="$1"
    local priority="${2:-medium}"
    local payload="$3"

    local task_id="task-${task_type}-$(date +%s)-$(openssl rand -hex 4)"

    sqlite3 "$TASK_DB" <<SQL
INSERT INTO tasks (task_id, task_type, priority, payload, status)
VALUES ('$task_id', '$task_type', '$priority', '$payload', 'pending');
SQL

    # Update orchestrator task queue
    sqlite3 "$ORCHESTRATOR_DB" <<SQL
INSERT INTO task_queue (task_id, task_type, priority, status)
VALUES ('$task_id', '$task_type', '$priority', 'pending');
SQL

    echo -e "${GREEN}✓${NC} Created task: $task_id ($task_type, priority: $priority)"
}

# Assign task to agent
assign_task() {
    local task_id="$1"
    local agent_id="$2"

    sqlite3 "$TASK_DB" <<SQL
UPDATE tasks
SET assigned_agent_id = '$agent_id',
    status = 'assigned',
    assigned_at = CURRENT_TIMESTAMP
WHERE task_id = '$task_id';
SQL

    sqlite3 "$ORCHESTRATOR_DB" <<SQL
UPDATE task_queue
SET assigned_to = '$agent_id',
    status = 'active',
    started_at = CURRENT_TIMESTAMP
WHERE task_id = '$task_id';

UPDATE agents
SET status = 'active',
    current_task = '$task_id'
WHERE agent_id = '$agent_id';
SQL

    echo -e "${GREEN}✓${NC} Assigned task $task_id to agent $agent_id"
}

# Auto-assign tasks to available agents
auto_assign_tasks() {
    echo -e "${BOLD}${CYAN}═══ AUTO-ASSIGNING TASKS ═══${NC}"
    echo ""

    # Get pending tasks
    local pending=$(sqlite3 "$TASK_DB" "SELECT COUNT(*) FROM tasks WHERE status='pending';" 2>/dev/null || echo 0)

    # Get idle agents
    local idle=$(sqlite3 "$ORCHESTRATOR_DB" "SELECT COUNT(*) FROM agents WHERE status='idle';" 2>/dev/null || echo 0)

    echo -e "${CYAN}Pending Tasks:${NC} $pending"
    echo -e "${CYAN}Idle Agents:${NC} $idle"
    echo ""

    if [ $pending -eq 0 ]; then
        echo -e "${YELLOW}No pending tasks${NC}"
        return
    fi

    if [ $idle -eq 0 ]; then
        echo -e "${YELLOW}No idle agents available${NC}"
        return
    fi

    # Assign tasks to agents (intelligent matching)
    local assigned=0
    local max_assign=$((pending < idle ? pending : idle))

    sqlite3 "$TASK_DB" "SELECT task_id, task_type FROM tasks WHERE status='pending' LIMIT $max_assign;" | \
    while IFS='|' read -r task_id task_type; do
        # Find matching agent
        local agent_id=$(sqlite3 "$ORCHESTRATOR_DB" \
            "SELECT agent_id FROM agents WHERE status='idle' AND agent_type='$task_type' LIMIT 1;" \
            2>/dev/null)

        # If no exact match, get any idle agent
        if [ -z "$agent_id" ]; then
            agent_id=$(sqlite3 "$ORCHESTRATOR_DB" \
                "SELECT agent_id FROM agents WHERE status='idle' LIMIT 1;" \
                2>/dev/null)
        fi

        if [ -n "$agent_id" ]; then
            assign_task "$task_id" "$agent_id"
            ((assigned++))
        fi
    done

    echo ""
    echo -e "${GREEN}✓ Assigned $assigned tasks${NC}"
}

# Generate random tasks for testing
generate_test_tasks() {
    local count="$1"

    echo -e "${BOLD}${PURPLE}═══ GENERATING $count TEST TASKS ═══${NC}"
    echo ""

    local task_types=("code-generation" "code-review" "data-analysis" "testing" "deployment" "monitoring")
    local priorities=("low" "medium" "high" "urgent")

    for i in $(seq 1 $count); do
        local task_type="${task_types[$((RANDOM % ${#task_types[@]}))]}"
        local priority="${priorities[$((RANDOM % ${#priorities[@]}))]}"

        create_task "$task_type" "$priority" "Test payload $i" > /dev/null

        if [ $((i % 50)) -eq 0 ]; then
            echo -e "${CYAN}  Generated $i/$count tasks...${NC}"
        fi
    done

    echo ""
    echo -e "${GREEN}✓ Generated $count tasks${NC}"
}

# Complete task
complete_task() {
    local task_id="$1"
    local result="${2:-success}"

    sqlite3 "$TASK_DB" <<SQL
UPDATE tasks
SET status = 'completed',
    completed_at = CURRENT_TIMESTAMP,
    result = '$result'
WHERE task_id = '$task_id';
SQL

    sqlite3 "$ORCHESTRATOR_DB" <<SQL
UPDATE task_queue
SET status = 'completed',
    completed_at = CURRENT_TIMESTAMP
WHERE task_id = '$task_id';

UPDATE agents
SET status = 'idle',
    current_task = NULL,
    tasks_completed = tasks_completed + 1
WHERE current_task = '$task_id';
SQL

    echo -e "${GREEN}✓${NC} Completed task: $task_id"
}

# Show task distribution
show_distribution() {
    echo -e "${CYAN}━━━ Task Distribution by Type ━━━${NC}"
    echo ""

    sqlite3 -column "$TASK_DB" "
        SELECT
            task_type,
            COUNT(*) as total,
            SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as pending,
            SUM(CASE WHEN status='assigned' THEN 1 ELSE 0 END) as assigned,
            SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed
        FROM tasks
        GROUP BY task_type;
    " 2>/dev/null

    echo ""
    echo -e "${CYAN}━━━ Task Distribution by Priority ━━━${NC}"
    echo ""

    sqlite3 -column "$TASK_DB" "
        SELECT
            priority,
            COUNT(*) as total,
            SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as pending
        FROM tasks
        GROUP BY priority
        ORDER BY
            CASE priority
                WHEN 'urgent' THEN 1
                WHEN 'high' THEN 2
                WHEN 'medium' THEN 3
                WHEN 'low' THEN 4
            END;
    " 2>/dev/null

    echo ""
}

# Show stats
show_stats() {
    echo -e "${CYAN}━━━ Task System Statistics ━━━${NC}"
    echo ""

    local total=$(sqlite3 "$TASK_DB" "SELECT COUNT(*) FROM tasks;" 2>/dev/null || echo 0)
    local pending=$(sqlite3 "$TASK_DB" "SELECT COUNT(*) FROM tasks WHERE status='pending';" 2>/dev/null || echo 0)
    local assigned=$(sqlite3 "$TASK_DB" "SELECT COUNT(*) FROM tasks WHERE status='assigned';" 2>/dev/null || echo 0)
    local completed=$(sqlite3 "$TASK_DB" "SELECT COUNT(*) FROM tasks WHERE status='completed';" 2>/dev/null || echo 0)

    echo -e "${CYAN}Total Tasks:${NC} $total"
    echo -e "${CYAN}Pending:${NC} $pending"
    echo -e "${CYAN}Assigned:${NC} $assigned"
    echo -e "${CYAN}Completed:${NC} $completed"

    if [ $total -gt 0 ]; then
        local completion_rate=$((100 * completed / total))
        echo -e "${CYAN}Completion Rate:${NC} ${completion_rate}%"
    fi

    echo ""
}

# Process tasks (simulate)
process_tasks() {
    local count="${1:-10}"

    echo -e "${BOLD}${GREEN}═══ PROCESSING $count TASKS ═══${NC}"
    echo ""

    # Auto-assign first
    auto_assign_tasks

    echo ""
    echo -e "${CYAN}Simulating task processing...${NC}"

    # Complete assigned tasks
    sqlite3 "$TASK_DB" "SELECT task_id FROM tasks WHERE status='assigned' LIMIT $count;" | \
    while read -r task_id; do
        sleep 0.1 # Simulate processing
        complete_task "$task_id" "success" > /dev/null
    done

    echo -e "${GREEN}✓ Processed $count tasks${NC}"
}

# Help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Distributed Task Queue System${NC}

Distributes tasks across 30,000 agents intelligently

USAGE:
    blackroad-task-distribution-system.sh <command> [args]

COMMANDS:
    init                        Initialize task system
    create <type> [priority]    Create a task
    assign <task_id> <agent_id> Assign task to agent
    auto-assign                 Auto-assign pending tasks
    complete <task_id>          Mark task as completed
    generate <count>            Generate test tasks
    process [count]             Process N tasks
    distribution                Show task distribution
    stats                       Show statistics
    help                        Show this help

TASK TYPES:
    code-generation, code-review, data-analysis,
    testing, deployment, monitoring, refactoring,
    documentation, security-scan, performance-test

PRIORITIES:
    urgent, high, medium, low

EXAMPLES:
    # Initialize
    blackroad-task-distribution-system.sh init

    # Generate 1000 test tasks
    blackroad-task-distribution-system.sh generate 1000

    # Auto-assign tasks to agents
    blackroad-task-distribution-system.sh auto-assign

    # Process 100 tasks
    blackroad-task-distribution-system.sh process 100

EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        create)
            create_task "$2" "$3" "$4"
            ;;
        assign)
            assign_task "$2" "$3"
            ;;
        auto-assign)
            auto_assign_tasks
            ;;
        complete)
            complete_task "$2" "$3"
            ;;
        generate)
            generate_test_tasks "${2:-100}"
            ;;
        process)
            process_tasks "${2:-10}"
            ;;
        distribution)
            show_distribution
            ;;
        stats)
            show_stats
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
