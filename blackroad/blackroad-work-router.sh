#!/bin/bash
# [ROUTER] - BlackRoad Intelligent Work Router
# Routes tasks to best-suited Claude agents
# Version: 1.0.0

set -e

ROUTER_DIR="$HOME/.blackroad/router"
ROUTER_DB="$ROUTER_DIR/agents.db"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize work router
init_router() {
    echo -e "${BLUE}[ROUTER]${NC} Initializing intelligent work router..."

    mkdir -p "$ROUTER_DIR"

    # Create database for agents, skills, and task assignments
    sqlite3 "$ROUTER_DB" <<EOF
CREATE TABLE IF NOT EXISTS agents (
    id TEXT PRIMARY KEY,
    name TEXT,
    skills TEXT,
    status TEXT DEFAULT 'available',
    current_workload INTEGER DEFAULT 0,
    total_tasks_completed INTEGER DEFAULT 0,
    success_rate REAL DEFAULT 100.0,
    registered_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_active TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    required_skills TEXT,
    priority TEXT DEFAULT 'medium',
    assigned_to TEXT,
    status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    assigned_at TEXT,
    completed_at TEXT,
    FOREIGN KEY (assigned_to) REFERENCES agents(id)
);

CREATE TABLE IF NOT EXISTS skill_matches (
    task_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    match_score REAL NOT NULL,
    calculated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id),
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);

CREATE TABLE IF NOT EXISTS task_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    action TEXT NOT NULL,
    details TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned ON tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);
CREATE INDEX IF NOT EXISTS idx_skill_matches_task ON skill_matches(task_id);
EOF

    echo -e "${GREEN}[ROUTER]${NC} Work router initialized at: $ROUTER_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "work-router" "Initialized [ROUTER] intelligent work routing system" "coordination,router,tasks" 2>/dev/null || true
    fi
}

# Register agent with skills
register_agent() {
    local agent_id="${MY_CLAUDE:-unknown-agent}"
    local name="${1:-$agent_id}"
    local skills="$2"

    if [ -z "$skills" ]; then
        echo -e "${RED}[ROUTER]${NC} Skills required (comma-separated)"
        echo -e "${CYAN}Example:${NC} python,api,cloudflare,fastapi,docker"
        return 1
    fi

    # Register or update agent
    sqlite3 "$ROUTER_DB" <<EOF
INSERT OR REPLACE INTO agents (id, name, skills, status, last_active)
VALUES (
    '${agent_id}',
    '${name}',
    '${skills}',
    'available',
    datetime('now')
);
EOF

    echo -e "${GREEN}[ROUTER]${NC} ✓ Agent registered!"
    echo -e "${CYAN}Agent ID:${NC} $agent_id"
    echo -e "${CYAN}Name:${NC} $name"
    echo -e "${CYAN}Skills:${NC} $skills"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log collaboration "agent-skills" "$agent_id registered with skills: $skills" "coordination,router,skills,collaboration" 2>/dev/null || true
    fi
}

# Update agent status
update_status() {
    local agent_id="${MY_CLAUDE:-unknown-agent}"
    local new_status="$1"

    if [ -z "$new_status" ]; then
        echo -e "${RED}[ROUTER]${NC} Status required: available, busy, offline"
        return 1
    fi

    sqlite3 "$ROUTER_DB" <<EOF
UPDATE agents
SET status='${new_status}', last_active=datetime('now')
WHERE id='${agent_id}';
EOF

    echo -e "${GREEN}[ROUTER]${NC} Status updated to: $new_status"
}

# Create new task
create_task() {
    local title="$1"
    local description="$2"
    local required_skills="$3"
    local priority="${4:-medium}"

    if [ -z "$title" ]; then
        echo -e "${RED}[ROUTER]${NC} Task title required"
        return 1
    fi

    local task_id="task-$(date +%s)-$(openssl rand -hex 4)"

    sqlite3 "$ROUTER_DB" <<EOF
INSERT INTO tasks (id, title, description, required_skills, priority)
VALUES (
    '${task_id}',
    '${title}',
    '${description}',
    '${required_skills}',
    '${priority}'
);
EOF

    echo -e "${GREEN}[ROUTER]${NC} ✓ Task created!"
    echo -e "${CYAN}Task ID:${NC} $task_id"
    echo -e "${CYAN}Title:${NC} $title"
    echo -e "${CYAN}Required Skills:${NC} ${required_skills:-any}"
    echo -e "${CYAN}Priority:${NC} $priority"

    # Auto-route task
    echo ""
    echo -e "${BLUE}[ROUTER]${NC} Finding best agent..."
    route_task "$task_id"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "task" "$task_id: $title" "coordination,router,task" 2>/dev/null || true
    fi
}

# Route task to best agent
route_task() {
    local task_id="$1"

    # Get task requirements
    local task_info=$(sqlite3 "$ROUTER_DB" "
        SELECT title, required_skills, priority
        FROM tasks
        WHERE id='${task_id}';
    " | tr '|' '\n')

    local required_skills=$(echo "$task_info" | sed -n '2p')

    if [ -z "$required_skills" ]; then
        # No specific skills required - assign to least busy available agent
        local best_agent=$(sqlite3 "$ROUTER_DB" "
            SELECT id FROM agents
            WHERE status='available'
            ORDER BY current_workload ASC, success_rate DESC
            LIMIT 1;
        ")
    else
        # Calculate skill match scores
        local best_score=0
        local best_agent=""

        sqlite3 "$ROUTER_DB" "SELECT id, skills, current_workload FROM agents WHERE status='available';" | while IFS='|' read -r agent_id agent_skills workload; do
            local score=0

            # Simple skill matching (count matching keywords)
            for skill in $(echo "$required_skills" | tr ',' ' '); do
                if echo "$agent_skills" | grep -qi "$skill"; then
                    ((score++))
                fi
            done

            # Adjust score for workload (prefer less busy agents)
            score=$(echo "$score - ($workload * 0.1)" | bc)

            # Save match score
            sqlite3 "$ROUTER_DB" <<EOF
INSERT INTO skill_matches (task_id, agent_id, match_score)
VALUES ('${task_id}', '${agent_id}', ${score});
EOF
        done

        # Get best match
        best_agent=$(sqlite3 "$ROUTER_DB" "
            SELECT agent_id FROM skill_matches
            WHERE task_id='${task_id}'
            ORDER BY match_score DESC
            LIMIT 1;
        ")
    fi

    if [ -z "$best_agent" ]; then
        echo -e "${YELLOW}[ROUTER]${NC} No available agents - task queued"
        return 0
    fi

    # Assign task
    sqlite3 "$ROUTER_DB" <<EOF
UPDATE tasks
SET assigned_to='${best_agent}', assigned_at=datetime('now'), status='assigned'
WHERE id='${task_id}';

UPDATE agents
SET current_workload = current_workload + 1
WHERE id='${best_agent}';

INSERT INTO task_history (task_id, agent_id, action, details)
VALUES ('${task_id}', '${best_agent}', 'assigned', 'Task automatically routed');
EOF

    echo -e "${GREEN}[ROUTER]${NC} ✓ Task assigned!"
    echo -e "${CYAN}Agent:${NC} $best_agent"

    # Get agent skills for display
    local agent_skills=$(sqlite3 "$ROUTER_DB" "SELECT skills FROM agents WHERE id='${best_agent}';")
    echo -e "${CYAN}Agent Skills:${NC} $agent_skills"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log collaboration "task-assigned" "$task_id assigned to $best_agent" "coordination,router,assignment" 2>/dev/null || true
    fi
}

# Show my assigned tasks
my_tasks() {
    local agent_id="${MY_CLAUDE:-unknown-agent}"

    echo -e "${BLUE}[ROUTER]${NC} My assigned tasks:"
    echo ""

    local task_count=$(sqlite3 "$ROUTER_DB" "
        SELECT COUNT(*) FROM tasks
        WHERE assigned_to='${agent_id}' AND status IN ('assigned', 'in_progress');
    ")

    if [ "$task_count" -eq 0 ]; then
        echo -e "${YELLOW}No assigned tasks${NC}"
        echo -e "${CYAN}Tip: Check available tasks with: list-tasks${NC}"
        return 0
    fi

    sqlite3 -column -header "$ROUTER_DB" <<EOF
SELECT
    substr(id, 1, 20) as task_id,
    title,
    priority,
    status,
    substr(assigned_at, 1, 16) as assigned
FROM tasks
WHERE assigned_to='${agent_id}' AND status IN ('assigned', 'in_progress')
ORDER BY
    CASE priority
        WHEN 'urgent' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        ELSE 4
    END,
    assigned_at;
EOF
}

# List all pending tasks
list_tasks() {
    echo -e "${BLUE}[ROUTER]${NC} Available tasks:"
    echo ""

    local pending_count=$(sqlite3 "$ROUTER_DB" "SELECT COUNT(*) FROM tasks WHERE status='pending';")

    if [ "$pending_count" -eq 0 ]; then
        echo -e "${GREEN}✓ No pending tasks${NC}"
        return 0
    fi

    sqlite3 -column -header "$ROUTER_DB" <<EOF
SELECT
    substr(id, 1, 20) as task_id,
    substr(title, 1, 40) as title,
    priority,
    substr(required_skills, 1, 30) as skills_needed
FROM tasks
WHERE status='pending'
ORDER BY
    CASE priority
        WHEN 'urgent' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        ELSE 4
    END,
    created_at;
EOF
}

# Mark task complete
complete_task() {
    local task_id="$1"
    local agent_id="${MY_CLAUDE:-unknown-agent}"

    if [ -z "$task_id" ]; then
        echo -e "${RED}[ROUTER]${NC} Task ID required"
        return 1
    fi

    # Verify task is assigned to this agent
    local assigned_agent=$(sqlite3 "$ROUTER_DB" "SELECT assigned_to FROM tasks WHERE id='${task_id}';")

    if [ "$assigned_agent" != "$agent_id" ]; then
        echo -e "${RED}[ROUTER]${NC} Task not assigned to you"
        return 1
    fi

    # Mark complete
    sqlite3 "$ROUTER_DB" <<EOF
UPDATE tasks
SET status='completed', completed_at=datetime('now')
WHERE id='${task_id}';

UPDATE agents
SET current_workload = current_workload - 1,
    total_tasks_completed = total_tasks_completed + 1
WHERE id='${agent_id}';

INSERT INTO task_history (task_id, agent_id, action, details)
VALUES ('${task_id}', '${agent_id}', 'completed', 'Task successfully completed');
EOF

    echo -e "${GREEN}[ROUTER]${NC} ✓ Task marked complete!"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log completed "task" "$agent_id completed $task_id" "coordination,router,completion" 2>/dev/null || true
    fi
}

# Show agent statistics
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🎯 WORK ROUTER STATISTICS 🎯                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_agents=$(sqlite3 "$ROUTER_DB" "SELECT COUNT(*) FROM agents;")
    local available_agents=$(sqlite3 "$ROUTER_DB" "SELECT COUNT(*) FROM agents WHERE status='available';")
    local total_tasks=$(sqlite3 "$ROUTER_DB" "SELECT COUNT(*) FROM tasks;")
    local pending_tasks=$(sqlite3 "$ROUTER_DB" "SELECT COUNT(*) FROM tasks WHERE status='pending';")
    local completed_tasks=$(sqlite3 "$ROUTER_DB" "SELECT COUNT(*) FROM tasks WHERE status='completed';")

    echo -e "${GREEN}Total Agents:${NC}      $total_agents"
    echo -e "${GREEN}Available:${NC}         $available_agents"
    echo -e "${GREEN}Total Tasks:${NC}       $total_tasks"
    echo -e "${YELLOW}Pending:${NC}           $pending_tasks"
    echo -e "${GREEN}Completed:${NC}         $completed_tasks"
    echo ""

    echo -e "${BLUE}Registered Agents:${NC}"
    sqlite3 -column -header "$ROUTER_DB" <<EOF
SELECT
    substr(id, 1, 30) as agent,
    status,
    current_workload as active,
    total_tasks_completed as done,
    substr(skills, 1, 30) as skills
FROM agents
ORDER BY total_tasks_completed DESC;
EOF

    echo ""
    echo -e "${BLUE}Task Status:${NC}"
    sqlite3 "$ROUTER_DB" <<EOF
SELECT
    status,
    COUNT(*) as count
FROM tasks
GROUP BY status
ORDER BY
    CASE status
        WHEN 'pending' THEN 1
        WHEN 'assigned' THEN 2
        WHEN 'in_progress' THEN 3
        WHEN 'completed' THEN 4
        ELSE 5
    END;
EOF
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Intelligent Work Router [ROUTER]${NC}

USAGE:
    blackroad-work-router.sh <command> [options]

COMMANDS:
    init                                Initialize work router
    register <name> <skills>            Register agent with skills
    status <available|busy|offline>     Update agent status
    create-task <title> <desc> <skills> <priority>  Create new task
    my-tasks                            Show my assigned tasks
    list-tasks                          Show all pending tasks
    complete <task-id>                  Mark task complete
    stats                               Show statistics
    help                                Show this help

EXAMPLES:
    # Initialize
    blackroad-work-router.sh init

    # Register with skills
    export MY_CLAUDE="claude-yourname-\$(date +%s)"
    blackroad-work-router.sh register "Claude Assistant" "python,api,cloudflare,docker"

    # Create task (will auto-route to best agent)
    blackroad-work-router.sh create-task \
        "Build API endpoint" \
        "FastAPI endpoint for user auth" \
        "python,fastapi,api" \
        "high"

    # View my tasks
    blackroad-work-router.sh my-tasks

    # Mark task complete
    blackroad-work-router.sh complete task-1234-abcd

    # Update status
    blackroad-work-router.sh status busy
    blackroad-work-router.sh status available

    # View stats
    blackroad-work-router.sh stats

SKILLS:
    Common skills: python, javascript, typescript, go, rust, api, fastapi,
    docker, k8s, cloudflare, aws, database, frontend, backend, devops

PRIORITIES:
    urgent, high, medium, low

ENVIRONMENT:
    MY_CLAUDE - Your Claude agent ID (required)

DATABASE: $ROUTER_DB
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_router
            ;;
        register)
            register_agent "$2" "$3"
            ;;
        status)
            update_status "$2"
            ;;
        create-task)
            create_task "$2" "$3" "$4" "${5:-medium}"
            ;;
        my-tasks)
            my_tasks
            ;;
        list-tasks)
            list_tasks
            ;;
        complete)
            complete_task "$2"
            ;;
        stats)
            show_stats
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[ROUTER]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
