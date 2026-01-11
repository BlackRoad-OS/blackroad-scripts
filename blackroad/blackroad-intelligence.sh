#!/bin/bash
# [INTELLIGENCE] - BlackRoad Pattern Intelligence System
# Learns from past work to improve future work
# Version: 1.0.0

set -e

INTELLIGENCE_DIR="$HOME/.blackroad/intelligence"
INTELLIGENCE_DB="$INTELLIGENCE_DIR/patterns.db"
MODELS_DIR="$INTELLIGENCE_DIR/models"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize intelligence system
init_intelligence() {
    echo -e "${BLUE}[INTELLIGENCE]${NC} Initializing pattern intelligence..."

    mkdir -p "$INTELLIGENCE_DIR" "$MODELS_DIR"

    # Create database for patterns and learnings
    sqlite3 "$INTELLIGENCE_DB" <<EOF
CREATE TABLE IF NOT EXISTS patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_type TEXT NOT NULL,
    context TEXT NOT NULL,
    solution TEXT NOT NULL,
    success_rate REAL DEFAULT 100.0,
    usage_count INTEGER DEFAULT 1,
    confidence REAL DEFAULT 0.5,
    source TEXT,
    discovered_at TEXT DEFAULT CURRENT_TIMESTAMP,
    last_used TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS best_practices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    practice TEXT NOT NULL,
    description TEXT,
    examples TEXT,
    effectiveness REAL DEFAULT 1.0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS failure_modes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    failure_type TEXT NOT NULL,
    context TEXT NOT NULL,
    cause TEXT NOT NULL,
    solution TEXT,
    prevention TEXT,
    occurrences INTEGER DEFAULT 1,
    last_seen TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS suggestions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_context TEXT NOT NULL,
    suggestion TEXT NOT NULL,
    reasoning TEXT,
    confidence REAL DEFAULT 0.5,
    accepted BOOLEAN DEFAULT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS learning_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    context TEXT NOT NULL,
    outcome TEXT NOT NULL,
    lesson TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_patterns_type ON patterns(pattern_type);
CREATE INDEX IF NOT EXISTS idx_patterns_success ON patterns(success_rate DESC);
CREATE INDEX IF NOT EXISTS idx_practices_category ON best_practices(category);
CREATE INDEX IF NOT EXISTS idx_failures_type ON failure_modes(failure_type);
EOF

    echo -e "${GREEN}[INTELLIGENCE]${NC} Pattern intelligence initialized at: $INTELLIGENCE_DB"

    # Seed with some basic patterns
    seed_patterns

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "intelligence" "Initialized [INTELLIGENCE] pattern learning system" "coordination,intelligence,ml" 2>/dev/null || true
    fi
}

# Seed initial patterns
seed_patterns() {
    sqlite3 "$INTELLIGENCE_DB" <<EOF
INSERT OR IGNORE INTO best_practices (category, practice, description, effectiveness)
VALUES
    ('deployment', 'Run tests before deploying', 'Always run full test suite before deployment', 0.95),
    ('deployment', 'Check health after deploy', 'Verify service health immediately after deployment', 0.90),
    ('git', 'Pull before push', 'Always pull latest changes before pushing to avoid conflicts', 0.85),
    ('coordination', 'Check for conflicts', 'Use conflict detector before claiming work', 0.95),
    ('coordination', 'Log to memory', 'Always log significant work to memory system', 0.90),
    ('api', 'Add error handling', 'Always include comprehensive error handling in API endpoints', 0.92),
    ('api', 'Validate inputs', 'Validate all user inputs before processing', 0.95),
    ('cloudflare', 'Test locally first', 'Test Cloudflare Workers/Pages locally before deploying', 0.88);

INSERT OR IGNORE INTO failure_modes (failure_type, context, cause, solution, prevention)
VALUES
    ('merge_conflict', 'Multiple agents editing same file', 'No coordination', 'Use conflict detector', 'Check claims before editing'),
    ('deployment_fail', 'Missing dependencies', 'Incomplete package.json', 'Add missing deps', 'Check dependencies before deploy'),
    ('api_timeout', 'Slow database query', 'No indexes', 'Add database indexes', 'Profile queries in development'),
    ('auth_failure', 'Expired credentials', 'No credential refresh', 'Implement auto-refresh', 'Monitor credential expiration');
EOF
}

# Learn from success
learn_success() {
    local context="$1"
    local what_worked="$2"

    if [ -z "$context" ] || [ -z "$what_worked" ]; then
        echo -e "${RED}[INTELLIGENCE]${NC} Context and solution required"
        return 1
    fi

    # Check if similar pattern exists
    local existing_pattern=$(sqlite3 "$INTELLIGENCE_DB" "
        SELECT id, usage_count, success_rate
        FROM patterns
        WHERE context LIKE '%${context}%'
        LIMIT 1;
    " | head -1)

    if [ -n "$existing_pattern" ]; then
        local pattern_id=$(echo "$existing_pattern" | cut -d'|' -f1)
        local usage=$(echo "$existing_pattern" | cut -d'|' -f2)
        local success=$(echo "$existing_pattern" | cut -d'|' -f3)

        # Update existing pattern
        local new_usage=$((usage + 1))
        local new_success=$(echo "($success * $usage + 100) / $new_usage" | bc -l)

        sqlite3 "$INTELLIGENCE_DB" "
            UPDATE patterns
            SET usage_count=${new_usage},
                success_rate=${new_success},
                last_used=datetime('now')
            WHERE id=${pattern_id};
        "

        echo -e "${GREEN}[INTELLIGENCE]${NC} ✓ Updated existing pattern (usage: $new_usage, success: ${new_success}%)"
    else
        # Create new pattern
        sqlite3 "$INTELLIGENCE_DB" <<EOF
INSERT INTO patterns (pattern_type, context, solution, confidence, source)
VALUES ('success', '${context}', '${what_worked}', 0.7, 'user-feedback');
EOF

        echo -e "${GREEN}[INTELLIGENCE]${NC} ✓ Learned new success pattern!"
    fi

    # Log learning event
    sqlite3 "$INTELLIGENCE_DB" "
        INSERT INTO learning_events (event_type, context, outcome, lesson)
        VALUES ('success', '${context}', 'worked', '${what_worked}');
    "

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "intelligence-learn" "Learned success pattern: $context" "coordination,intelligence,learning" 2>/dev/null || true
    fi
}

# Learn from failure
learn_failure() {
    local failure_type="$1"
    local what_failed="$2"
    local how_to_fix="$3"

    if [ -z "$failure_type" ] || [ -z "$what_failed" ]; then
        echo -e "${RED}[INTELLIGENCE]${NC} Failure type and description required"
        return 1
    fi

    # Record failure mode
    sqlite3 "$INTELLIGENCE_DB" <<EOF
INSERT INTO failure_modes (failure_type, context, cause, solution, prevention)
VALUES (
    '${failure_type}',
    '${what_failed}',
    'User reported',
    '${how_to_fix}',
    'Apply learned pattern'
)
ON CONFLICT DO UPDATE SET
    occurrences = occurrences + 1,
    last_seen = datetime('now');
EOF

    echo -e "${GREEN}[INTELLIGENCE]${NC} ✓ Failure mode recorded"
    echo -e "${YELLOW}This will help prevent similar failures in the future${NC}"

    # Log learning event
    sqlite3 "$INTELLIGENCE_DB" "
        INSERT INTO learning_events (event_type, context, outcome, lesson)
        VALUES ('failure', '${what_failed}', 'failed', '${how_to_fix}');
    "

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "intelligence-failure" "Learned from failure: $failure_type" "coordination,intelligence,learning" 2>/dev/null || true
    fi
}

# Get suggestions for task
suggest() {
    local task_description="$1"

    if [ -z "$task_description" ]; then
        echo -e "${RED}[INTELLIGENCE]${NC} Task description required"
        return 1
    fi

    echo -e "${BLUE}[INTELLIGENCE]${NC} Analyzing task: \"${task_description}\""
    echo ""

    # Extract keywords
    local keywords=$(echo "$task_description" | tr '[:upper:]' '[:lower:]' | tr -s '[:punct:][:space:]' '\n' | grep -v '^$' | head -10)

    # Find relevant patterns
    echo -e "${CYAN}Relevant Success Patterns:${NC}"
    local found_patterns=0

    for keyword in $keywords; do
        sqlite3 -column "$INTELLIGENCE_DB" "
            SELECT
                '  • ' || solution as suggestion,
                CAST(success_rate as INT) || '%' as success
            FROM patterns
            WHERE LOWER(context) LIKE '%${keyword}%'
            ORDER BY success_rate DESC, usage_count DESC
            LIMIT 3;
        " 2>/dev/null | grep -v '^$' | head -3
        found_patterns=1
    done

    if [ $found_patterns -eq 0 ]; then
        echo -e "${YELLOW}  No specific patterns found${NC}"
    fi

    echo ""
    echo -e "${CYAN}Best Practices:${NC}"

    # Find relevant best practices
    for keyword in $keywords; do
        sqlite3 -column "$INTELLIGENCE_DB" "
            SELECT DISTINCT
                '  • ' || practice as practice,
                description
            FROM best_practices
            WHERE LOWER(category) LIKE '%${keyword}%'
               OR LOWER(practice) LIKE '%${keyword}%'
            ORDER BY effectiveness DESC
            LIMIT 3;
        " 2>/dev/null | grep -v '^$'
    done

    echo ""
    echo -e "${CYAN}Common Pitfalls to Avoid:${NC}"

    # Find relevant failure modes
    for keyword in $keywords; do
        sqlite3 -column "$INTELLIGENCE_DB" "
            SELECT DISTINCT
                '  ⚠ ' || failure_type as warning,
                prevention
            FROM failure_modes
            WHERE LOWER(context) LIKE '%${keyword}%'
               OR LOWER(failure_type) LIKE '%${keyword}%'
            ORDER BY occurrences DESC
            LIMIT 3;
        " 2>/dev/null | grep -v '^$'
    done

    # Create suggestion record
    local suggestions_text=$(sqlite3 "$INTELLIGENCE_DB" "
        SELECT GROUP_CONCAT(solution, '; ')
        FROM patterns
        WHERE LOWER(context) LIKE '%$(echo "$task_description" | tr ' ' '%' | tr '[:upper:]' '[:lower:]')%'
        LIMIT 3;
    ")

    if [ -n "$suggestions_text" ]; then
        sqlite3 "$INTELLIGENCE_DB" "
            INSERT INTO suggestions (task_context, suggestion, reasoning, confidence)
            VALUES ('${task_description}', '${suggestions_text}', 'Based on historical patterns', 0.75);
        "
    fi
}

# Show insights
show_insights() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🧠 INTELLIGENCE INSIGHTS 🧠                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}Most Effective Patterns:${NC}"
    sqlite3 -column -header "$INTELLIGENCE_DB" <<EOF
SELECT
    substr(context, 1, 30) as pattern,
    CAST(success_rate as INT) || '%' as success,
    usage_count as used
FROM patterns
ORDER BY success_rate DESC, usage_count DESC
LIMIT 5;
EOF

    echo ""
    echo -e "${BLUE}Top Best Practices:${NC}"
    sqlite3 -column -header "$INTELLIGENCE_DB" <<EOF
SELECT
    category,
    substr(practice, 1, 40) as practice,
    CAST(effectiveness * 100 as INT) || '%' as score
FROM best_practices
ORDER BY effectiveness DESC
LIMIT 5;
EOF

    echo ""
    echo -e "${BLUE}Common Failure Modes:${NC}"
    sqlite3 -column -header "$INTELLIGENCE_DB" <<EOF
SELECT
    failure_type as type,
    occurrences as times,
    substr(prevention, 1, 40) as how_to_prevent
FROM failure_modes
ORDER BY occurrences DESC
LIMIT 5;
EOF

    echo ""
    local total_patterns=$(sqlite3 "$INTELLIGENCE_DB" "SELECT COUNT(*) FROM patterns;")
    local total_learnings=$(sqlite3 "$INTELLIGENCE_DB" "SELECT COUNT(*) FROM learning_events;")
    local total_suggestions=$(sqlite3 "$INTELLIGENCE_DB" "SELECT COUNT(*) FROM suggestions;")

    echo -e "${GREEN}Total Patterns Learned:${NC} $total_patterns"
    echo -e "${GREEN}Total Learning Events:${NC}  $total_learnings"
    echo -e "${GREEN}Suggestions Made:${NC}       $total_suggestions"
}

# Analyze patterns
analyze() {
    echo -e "${BLUE}[INTELLIGENCE]${NC} Analyzing patterns from memory..."

    # Analyze memory journal for patterns
    local journal="$HOME/.blackroad/memory/journals/master-journal.jsonl"

    if [ ! -f "$journal" ]; then
        echo -e "${YELLOW}[INTELLIGENCE]${NC} Memory journal not found"
        return 0
    fi

    # Find common successful actions
    local top_actions=$(cat "$journal" | jq -r '.action' | sort | uniq -c | sort -rn | head -5)

    echo -e "${CYAN}Most Common Actions:${NC}"
    echo "$top_actions"
    echo ""

    # Look for completion patterns
    local completions=$(grep '"action":"completed"' "$journal" | wc -l)
    local total_entries=$(wc -l < "$journal")
    local completion_rate=$(echo "scale=1; $completions * 100 / $total_entries" | bc)

    echo -e "${CYAN}Completion Rate:${NC} ${completion_rate}% ($completions of $total_entries)"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "intelligence-analysis" "Analyzed patterns: $total_entries events, ${completion_rate}% completion rate" "coordination,intelligence,analysis" 2>/dev/null || true
    fi
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Pattern Intelligence [INTELLIGENCE]${NC}

USAGE:
    blackroad-intelligence.sh <command> [options]

COMMANDS:
    init                                Initialize intelligence system
    learn-success <context> <solution>  Learn from successful approach
    learn-failure <type> <what> <fix>   Learn from failure
    suggest <task-description>          Get suggestions for task
    insights                            Show learned insights
    analyze                             Analyze patterns from memory
    help                                Show this help

EXAMPLES:
    # Initialize
    blackroad-intelligence.sh init

    # Learn from success
    blackroad-intelligence.sh learn-success \
        "cloudflare-deployment" \
        "Test locally first with wrangler dev"

    # Learn from failure
    blackroad-intelligence.sh learn-failure \
        "merge-conflict" \
        "Two agents edited same file" \
        "Use conflict detector before starting work"

    # Get suggestions
    blackroad-intelligence.sh suggest "Deploy API to Cloudflare Workers"
    blackroad-intelligence.sh suggest "Add authentication to FastAPI app"

    # View insights
    blackroad-intelligence.sh insights

    # Analyze patterns
    blackroad-intelligence.sh analyze

DATABASE: $INTELLIGENCE_DB
MODELS: $MODELS_DIR
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_intelligence
            ;;
        learn-success)
            learn_success "$2" "$3"
            ;;
        learn-failure)
            learn_failure "$2" "$3" "$4"
            ;;
        suggest)
            suggest "$2"
            ;;
        insights)
            show_insights
            ;;
        analyze)
            analyze
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[INTELLIGENCE]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
