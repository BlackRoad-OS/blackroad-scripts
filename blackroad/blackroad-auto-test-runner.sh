#!/bin/bash
# BlackRoad Automated Testing Framework
# Runs tests across all repos with intelligent test detection
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
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
TEST_DB="$HOME/.blackroad/auto-test/results.db"

# Initialize database
init_db() {
    mkdir -p "$(dirname "$TEST_DB")"

    sqlite3 "$TEST_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS test_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT NOT NULL,
    test_framework TEXT,
    started_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    duration_seconds REAL DEFAULT 0,
    total_tests INTEGER DEFAULT 0,
    passed_tests INTEGER DEFAULT 0,
    failed_tests INTEGER DEFAULT 0,
    skipped_tests INTEGER DEFAULT 0,
    status TEXT DEFAULT 'running',
    exit_code INTEGER DEFAULT 0,
    agent_id TEXT
);

CREATE TABLE IF NOT EXISTS test_failures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER,
    test_name TEXT NOT NULL,
    error_message TEXT,
    stack_trace TEXT,
    FOREIGN KEY (run_id) REFERENCES test_runs(id)
);

CREATE TABLE IF NOT EXISTS test_coverage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER,
    file_path TEXT NOT NULL,
    line_coverage REAL DEFAULT 0,
    branch_coverage REAL DEFAULT 0,
    FOREIGN KEY (run_id) REFERENCES test_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_runs_repo ON test_runs(repo);
CREATE INDEX IF NOT EXISTS idx_runs_status ON test_runs(status);
SQL

    echo -e "${GREEN}[AUTO-TEST]${NC} Database initialized!"
}

# Detect test framework in a repository
detect_test_framework() {
    local repo_path="$1"

    cd "$repo_path"

    # Node.js/JavaScript
    if [ -f "package.json" ]; then
        if grep -q "\"jest\"" package.json 2>/dev/null; then
            echo "jest"
            return
        elif grep -q "\"mocha\"" package.json 2>/dev/null; then
            echo "mocha"
            return
        elif grep -q "\"vitest\"" package.json 2>/dev/null; then
            echo "vitest"
            return
        fi
    fi

    # Python
    if [ -f "pytest.ini" ] || [ -f "setup.cfg" ] || find . -name "*_test.py" -o -name "test_*.py" 2>/dev/null | head -1 | grep -q .; then
        echo "pytest"
        return
    fi

    # Go
    if [ -f "go.mod" ] && find . -name "*_test.go" 2>/dev/null | head -1 | grep -q .; then
        echo "go-test"
        return
    fi

    echo "none"
}

# Run tests for a repository
run_tests() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${PURPLE}━━━ Testing $repo_name ━━━${NC}"

    cd "$repo_path"

    # Detect framework
    local framework=$(detect_test_framework "$repo_path")

    if [ "$framework" = "none" ]; then
        echo -e "${YELLOW}  No test framework detected${NC}"
        echo ""
        return
    fi

    echo -e "${CYAN}  Framework: $framework${NC}"

    # Start timing
    local start_time=$(date +%s)

    # Create test run record
    local run_id=$(sqlite3 "$TEST_DB" <<SQL
INSERT INTO test_runs (repo, test_framework, agent_id)
VALUES ('$repo_name', '$framework', '${MY_CLAUDE:-unknown}');
SELECT last_insert_rowid();
SQL
)

    # Run tests based on framework
    local test_output=""
    local exit_code=0

    case "$framework" in
        jest)
            echo -e "${CYAN}  Running Jest tests...${NC}"
            test_output=$(npm test -- --json 2>&1 || true)
            exit_code=$?
            ;;
        mocha)
            echo -e "${CYAN}  Running Mocha tests...${NC}"
            test_output=$(npm test 2>&1 || true)
            exit_code=$?
            ;;
        vitest)
            echo -e "${CYAN}  Running Vitest tests...${NC}"
            test_output=$(npm test 2>&1 || true)
            exit_code=$?
            ;;
        pytest)
            echo -e "${CYAN}  Running Pytest tests...${NC}"
            test_output=$(python3 -m pytest --tb=short 2>&1 || true)
            exit_code=$?
            ;;
        go-test)
            echo -e "${CYAN}  Running Go tests...${NC}"
            test_output=$(go test ./... -v 2>&1 || true)
            exit_code=$?
            ;;
    esac

    # End timing
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Parse results (simplified - would need more sophisticated parsing for each framework)
    local total_tests=0
    local passed_tests=0
    local failed_tests=0

    if echo "$test_output" | grep -q "passed\|PASS\|ok"; then
        passed_tests=$(echo "$test_output" | grep -o "passed\|PASS\|ok" | wc -l | tr -d ' ')
    fi

    if echo "$test_output" | grep -q "failed\|FAIL\|FAILED"; then
        failed_tests=$(echo "$test_output" | grep -o "failed\|FAIL\|FAILED" | wc -l | tr -d ' ')
    fi

    total_tests=$((passed_tests + failed_tests))

    # Determine status
    local status="success"
    if [ $exit_code -ne 0 ]; then
        status="failed"
    fi

    # Display results
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}  ✓ Tests passed: $passed_tests${NC}"
    else
        echo -e "${RED}  ✗ Tests failed: $failed_tests${NC}"
        echo -e "${YELLOW}  Exit code: $exit_code${NC}"
    fi
    echo -e "${CYAN}  Duration: ${duration}s${NC}"

    # Update database
    sqlite3 "$TEST_DB" <<SQL
UPDATE test_runs
SET completed_at=CURRENT_TIMESTAMP,
    duration_seconds=$duration,
    total_tests=$total_tests,
    passed_tests=$passed_tests,
    failed_tests=$failed_tests,
    status='$status',
    exit_code=$exit_code
WHERE id=$run_id;
SQL

    echo ""
}

# Run tests across all repositories
run_all_tests() {
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}║   🧪 AUTOMATED TESTING FRAMEWORK 🧪                    ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_repos=0
    local passed_repos=0
    local failed_repos=0

    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            ((total_repos++))

            run_tests "$repo_path"

            # Check if tests passed
            if [ $? -eq 0 ]; then
                ((passed_repos++))
            else
                ((failed_repos++))
            fi
        done
    fi

    echo -e "${GREEN}━━━ Testing Complete ━━━${NC}"
    echo ""

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log completed "auto-test-run" "Ran automated tests across all repositories. Check stats for results." "testing,automation,ci" 2>/dev/null || true
    fi
}

# Show test statistics
show_stats() {
    echo -e "${CYAN}━━━ Testing Statistics ━━━${NC}"
    echo ""

    if [ -f "$TEST_DB" ]; then
        echo -e "${PURPLE}Overall Summary:${NC}"
        sqlite3 -column "$TEST_DB" "
            SELECT
                COUNT(*) as total_runs,
                SUM(total_tests) as total_tests,
                SUM(passed_tests) as passed,
                SUM(failed_tests) as failed,
                ROUND(AVG(duration_seconds), 2) as avg_duration_sec
            FROM test_runs;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Success Rate by Repository:${NC}"
        sqlite3 -column "$TEST_DB" "
            SELECT
                substr(repo, 1, 35) as repository,
                COUNT(*) as runs,
                SUM(CASE WHEN status='success' THEN 1 ELSE 0 END) as successful,
                ROUND(100.0 * SUM(CASE WHEN status='success' THEN 1 ELSE 0 END) / COUNT(*), 1) || '%' as success_rate
            FROM test_runs
            GROUP BY repo
            ORDER BY success_rate DESC;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Test Frameworks in Use:${NC}"
        sqlite3 -column "$TEST_DB" "
            SELECT
                test_framework as framework,
                COUNT(DISTINCT repo) as repos
            FROM test_runs
            GROUP BY test_framework;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Recent Failures:${NC}"
        sqlite3 -column "$TEST_DB" "
            SELECT
                substr(repo, 1, 30) as repository,
                failed_tests as failures,
                ROUND(duration_seconds, 1) || 's' as duration,
                substr(completed_at, 1, 19) as when
            FROM test_runs
            WHERE status='failed'
            ORDER BY completed_at DESC
            LIMIT 10;
        " 2>/dev/null || echo "No recent failures! 🎉"
    else
        echo "No test data found. Run 'run-all' first."
    fi

    echo ""
}

# Watch mode - continuously run tests
watch_mode() {
    local repo_path="$1"

    if [ -z "$repo_path" ]; then
        echo -e "${RED}[AUTO-TEST]${NC} Repository path required for watch mode"
        return 1
    fi

    echo -e "${CYAN}Starting watch mode for $(basename "$repo_path")...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    while true; do
        run_tests "$repo_path"
        sleep 5
    done
}

# Generate test report
generate_report() {
    local output_file="${1:-test-report-$(date +%Y%m%d-%H%M%S).html}"

    echo -e "${CYAN}Generating test report...${NC}"

    if [ ! -f "$TEST_DB" ]; then
        echo "No test data found"
        return
    fi

    cat > "$output_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>BlackRoad Test Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #0a0a0a; color: #fff; }
        h1 { color: #F5A623; }
        h2 { color: #FF1D6C; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; background: #1a1a1a; }
        th { background: #2979FF; color: #fff; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #333; }
        tr:hover { background: #252525; }
        .success { color: #4CAF50; }
        .failed { color: #f44336; }
        .stats { background: #1a1a1a; padding: 20px; border-radius: 8px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>🧪 BlackRoad Test Report</h1>
    <p>Generated: <span id="timestamp"></span></p>
    <script>document.getElementById('timestamp').textContent = new Date().toLocaleString();</script>

    <div class="stats">
        <h2>📊 Summary</h2>
EOF

    # Add summary stats
    sqlite3 -html "$TEST_DB" "
        SELECT
            COUNT(*) as 'Total Test Runs',
            SUM(total_tests) as 'Total Tests',
            SUM(passed_tests) as 'Passed',
            SUM(failed_tests) as 'Failed',
            ROUND(100.0 * SUM(passed_tests) / NULLIF(SUM(total_tests), 0), 2) || '%' as 'Pass Rate'
        FROM test_runs;
    " >> "$output_file"

    cat >> "$output_file" <<'EOF'
    </div>

    <h2>📁 Repository Results</h2>
EOF

    # Add repo results
    sqlite3 -html "$TEST_DB" "
        SELECT
            repo as 'Repository',
            test_framework as 'Framework',
            total_tests as 'Tests',
            passed_tests as 'Passed',
            failed_tests as 'Failed',
            ROUND(duration_seconds, 2) || 's' as 'Duration',
            status as 'Status'
        FROM test_runs
        ORDER BY completed_at DESC;
    " >> "$output_file"

    cat >> "$output_file" <<'EOF'
</body>
</html>
EOF

    echo -e "${GREEN}✓ Report generated: $output_file${NC}"
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Automated Testing Framework${NC}

Runs tests across all repositories with intelligent framework detection.

USAGE:
    blackroad-auto-test-runner.sh <command> [args]

COMMANDS:
    init                    Initialize test database
    run-all                 Run tests across all repositories
    run <repo-path>         Run tests for specific repository
    watch <repo-path>       Watch mode - continuously run tests
    stats                   Show testing statistics
    report [file]           Generate HTML test report
    help                    Show this help

EXAMPLES:
    # Run all tests
    blackroad-auto-test-runner.sh run-all

    # Run tests for one repo
    blackroad-auto-test-runner.sh run ~/projects/blackroad-api

    # Watch mode
    blackroad-auto-test-runner.sh watch ~/projects/blackroad-api

    # View stats
    blackroad-auto-test-runner.sh stats

    # Generate report
    blackroad-auto-test-runner.sh report test-results.html

SUPPORTED FRAMEWORKS:
    ✓ Jest (Node.js)
    ✓ Mocha (Node.js)
    ✓ Vitest (Node.js)
    ✓ Pytest (Python)
    ✓ Go test (Go)

FEATURES:
    ✓ Automatic framework detection
    ✓ Test result tracking
    ✓ Failure analysis
    ✓ Duration monitoring
    ✓ Watch mode for development
    ✓ HTML report generation
    ✓ Memory system integration

DATABASE: $TEST_DB
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        run-all)
            init_db
            run_all_tests
            ;;
        run)
            if [ -z "$2" ]; then
                echo -e "${RED}[AUTO-TEST]${NC} Repository path required"
                exit 1
            fi
            init_db
            run_tests "$2"
            ;;
        watch)
            init_db
            watch_mode "$2"
            ;;
        stats)
            show_stats
            ;;
        report)
            generate_report "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[AUTO-TEST]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
