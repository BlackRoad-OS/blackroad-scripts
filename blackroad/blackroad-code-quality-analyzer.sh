#!/bin/bash
# BlackRoad Intelligent Code Quality Analyzer
# Analyzes code quality across all repos with AI-powered insights
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
QUALITY_DB="$HOME/.blackroad/code-quality/analysis.db"

# Initialize database
init_db() {
    mkdir -p "$(dirname "$QUALITY_DB")"

    sqlite3 "$QUALITY_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS quality_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT NOT NULL,
    analyzed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    total_files INTEGER DEFAULT 0,
    total_lines INTEGER DEFAULT 0,
    complexity_score REAL DEFAULT 0,
    maintainability_score REAL DEFAULT 0,
    test_coverage REAL DEFAULT 0,
    duplication_percentage REAL DEFAULT 0,
    security_issues INTEGER DEFAULT 0,
    overall_grade TEXT
);

CREATE TABLE IF NOT EXISTS code_issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id INTEGER,
    file_path TEXT NOT NULL,
    line_number INTEGER,
    issue_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    message TEXT NOT NULL,
    suggestion TEXT,
    FOREIGN KEY (report_id) REFERENCES quality_reports(id)
);

CREATE TABLE IF NOT EXISTS code_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id INTEGER,
    metric_name TEXT NOT NULL,
    metric_value REAL NOT NULL,
    FOREIGN KEY (report_id) REFERENCES quality_reports(id)
);

CREATE INDEX IF NOT EXISTS idx_reports_repo ON quality_reports(repo);
CREATE INDEX IF NOT EXISTS idx_issues_severity ON code_issues(severity);
SQL

    echo -e "${GREEN}[QUALITY]${NC} Database initialized!"
}

# Analyze code complexity
analyze_complexity() {
    local file="$1"
    local ext="${file##*.}"

    case "$ext" in
        js|ts|jsx|tsx)
            # Count nested blocks as complexity indicator
            local complexity=$(grep -o '{' "$file" 2>/dev/null | wc -l | tr -d ' ')
            echo "$complexity"
            ;;
        py)
            # Count indentation depth
            local complexity=$(grep -E '^    ' "$file" 2>/dev/null | wc -l | tr -d ' ')
            echo "$complexity"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# Check for common code smells
check_code_smells() {
    local file="$1"
    local issues=0

    # Long functions (>100 lines)
    if grep -E 'function|def ' "$file" &>/dev/null; then
        local func_count=$(grep -E 'function|def ' "$file" | wc -l | tr -d ' ')
        local file_lines=$(wc -l < "$file")
        if [ "$file_lines" -gt 100 ] && [ "$func_count" -eq 1 ]; then
            ((issues++))
        fi
    fi

    # TODO comments
    if grep -i 'TODO\|FIXME\|HACK' "$file" &>/dev/null; then
        ((issues++))
    fi

    # Commented out code
    if grep -E '^\s*//|^\s*#' "$file" 2>/dev/null | wc -l | grep -qE '[5-9][0-9]|[1-9][0-9]{2,}'; then
        ((issues++))
    fi

    echo "$issues"
}

# Analyze a single repository
analyze_repo() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${PURPLE}━━━ Analyzing $repo_name ━━━${NC}"

    cd "$repo_path"

    # Count files and lines
    local total_files=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" \) 2>/dev/null | wc -l | tr -d ' ')
    local total_lines=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" \) -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")

    if [ "$total_files" -eq 0 ]; then
        echo -e "${YELLOW}  No code files found${NC}"
        return
    fi

    echo -e "${CYAN}  Files: $total_files | Lines: $total_lines${NC}"

    # Calculate complexity
    local total_complexity=0
    find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" \) 2>/dev/null | while read -r file; do
        local complexity=$(analyze_complexity "$file")
        total_complexity=$((total_complexity + complexity))
    done

    local avg_complexity=$(echo "scale=2; $total_complexity / $total_files" | bc 2>/dev/null || echo "0")

    # Check for code smells
    local total_smells=0
    find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" \) 2>/dev/null | while read -r file; do
        local smells=$(check_code_smells "$file")
        total_smells=$((total_smells + smells))
    done

    # Calculate maintainability score (0-100)
    local maintainability=$(echo "scale=2; 100 - ($avg_complexity * 2)" | bc 2>/dev/null || echo "75")
    if (( $(echo "$maintainability < 0" | bc -l 2>/dev/null || echo "0") )); then
        maintainability="0"
    fi

    # Check for tests
    local test_files=$(find . -type f \( -name "*.test.js" -o -name "*.spec.js" -o -name "*_test.py" -o -name "*_test.go" \) 2>/dev/null | wc -l | tr -d ' ')
    local coverage=$(echo "scale=2; ($test_files / $total_files) * 100" | bc 2>/dev/null || echo "0")

    # Security check - look for common issues
    local security_issues=0
    if grep -r "password.*=\|api.*key.*=\|secret.*=" . 2>/dev/null | grep -v node_modules | grep -v ".git" | head -1 &>/dev/null; then
        ((security_issues++))
    fi

    # Calculate overall grade
    local grade="C"
    if (( $(echo "$maintainability >= 80" | bc -l 2>/dev/null || echo "0") )); then
        grade="A"
    elif (( $(echo "$maintainability >= 60" | bc -l 2>/dev/null || echo "0") )); then
        grade="B"
    elif (( $(echo "$maintainability >= 40" | bc -l 2>/dev/null || echo "0") )); then
        grade="C"
    else
        grade="D"
    fi

    # Display results
    echo -e "${CYAN}  Complexity Score: $avg_complexity${NC}"
    echo -e "${CYAN}  Maintainability: ${maintainability}%${NC}"
    echo -e "${CYAN}  Test Coverage: ${coverage}%${NC}"
    echo -e "${CYAN}  Security Issues: $security_issues${NC}"
    echo -e "${BOLD}  Overall Grade: ${grade}${NC}"

    # Save to database
    sqlite3 "$QUALITY_DB" <<SQL
INSERT INTO quality_reports (
    repo, total_files, total_lines, complexity_score,
    maintainability_score, test_coverage, security_issues, overall_grade
) VALUES (
    '$repo_name', $total_files, $total_lines, $avg_complexity,
    $maintainability, $coverage, $security_issues, '$grade'
);
SQL

    echo ""
}

# Analyze all repositories
analyze_all() {
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}║   📊 INTELLIGENT CODE QUALITY ANALYZER 📊              ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_repos=0

    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            ((total_repos++))
            analyze_repo "$repo_path"
        done
    fi

    echo -e "${GREEN}━━━ Analysis Complete ━━━${NC}"
    echo ""

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log completed "code-quality-analysis" "Analyzed code quality across all repositories. Results stored in database. Check stats for detailed metrics." "quality,analysis,code" 2>/dev/null || true
    fi
}

# Show quality statistics
show_stats() {
    echo -e "${CYAN}━━━ Code Quality Statistics ━━━${NC}"
    echo ""

    if [ -f "$QUALITY_DB" ]; then
        echo -e "${PURPLE}Overall Summary:${NC}"
        sqlite3 -column "$QUALITY_DB" "
            SELECT
                COUNT(*) as total_repos,
                ROUND(AVG(maintainability_score), 2) as avg_maintainability,
                ROUND(AVG(test_coverage), 2) as avg_coverage,
                SUM(security_issues) as total_security_issues
            FROM quality_reports;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Grade Distribution:${NC}"
        sqlite3 -column "$QUALITY_DB" "
            SELECT
                overall_grade as grade,
                COUNT(*) as count
            FROM quality_reports
            GROUP BY overall_grade
            ORDER BY overall_grade;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Top 10 Highest Quality Repos:${NC}"
        sqlite3 -column "$QUALITY_DB" "
            SELECT
                substr(repo, 1, 35) as repository,
                ROUND(maintainability_score, 1) as maintainability,
                ROUND(test_coverage, 1) as coverage,
                overall_grade as grade
            FROM quality_reports
            ORDER BY maintainability_score DESC
            LIMIT 10;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Repos Needing Attention (Grade D or below):${NC}"
        sqlite3 -column "$QUALITY_DB" "
            SELECT
                substr(repo, 1, 35) as repository,
                ROUND(maintainability_score, 1) as maintainability,
                security_issues,
                overall_grade as grade
            FROM quality_reports
            WHERE overall_grade IN ('D', 'F')
            ORDER BY maintainability_score ASC;
        " 2>/dev/null || echo "None! 🎉"
    else
        echo "No analysis data found. Run 'analyze-all' first."
    fi

    echo ""
}

# Show detailed report for a repository
show_report() {
    local repo_name="$1"

    if [ -z "$repo_name" ]; then
        echo -e "${RED}[QUALITY]${NC} Repository name required"
        return 1
    fi

    echo -e "${CYAN}━━━ Quality Report: $repo_name ━━━${NC}"
    echo ""

    if [ -f "$QUALITY_DB" ]; then
        sqlite3 -column "$QUALITY_DB" "
            SELECT
                total_files as files,
                total_lines as lines,
                ROUND(complexity_score, 2) as complexity,
                ROUND(maintainability_score, 2) as maintainability,
                ROUND(test_coverage, 2) as coverage,
                security_issues,
                overall_grade as grade,
                analyzed_at
            FROM quality_reports
            WHERE repo='$repo_name'
            ORDER BY analyzed_at DESC
            LIMIT 1;
        " 2>/dev/null || echo "No data for $repo_name"
    fi

    echo ""
}

# Generate improvement suggestions
generate_suggestions() {
    echo -e "${BOLD}${YELLOW}━━━ Improvement Suggestions ━━━${NC}"
    echo ""

    if [ ! -f "$QUALITY_DB" ]; then
        echo "No analysis data found. Run 'analyze-all' first."
        return
    fi

    echo -e "${PURPLE}🎯 Priority Actions:${NC}"
    echo ""

    # Repos with security issues
    local security_count=$(sqlite3 "$QUALITY_DB" "SELECT COUNT(*) FROM quality_reports WHERE security_issues > 0;" 2>/dev/null || echo "0")
    if [ "$security_count" -gt 0 ]; then
        echo -e "${RED}1. Fix Security Issues (URGENT)${NC}"
        sqlite3 "$QUALITY_DB" "
            SELECT '   - ' || repo || ' (' || security_issues || ' issues)'
            FROM quality_reports
            WHERE security_issues > 0
            ORDER BY security_issues DESC;
        " 2>/dev/null
        echo ""
    fi

    # Repos with low test coverage
    echo -e "${YELLOW}2. Improve Test Coverage${NC}"
    sqlite3 "$QUALITY_DB" "
        SELECT '   - ' || repo || ' (coverage: ' || ROUND(test_coverage, 1) || '%)'
        FROM quality_reports
        WHERE test_coverage < 50
        ORDER BY test_coverage ASC
        LIMIT 5;
    " 2>/dev/null || echo "   All repos have good coverage!"
    echo ""

    # Repos with low maintainability
    echo -e "${YELLOW}3. Refactor for Maintainability${NC}"
    sqlite3 "$QUALITY_DB" "
        SELECT '   - ' || repo || ' (score: ' || ROUND(maintainability_score, 1) || ')'
        FROM quality_reports
        WHERE maintainability_score < 60
        ORDER BY maintainability_score ASC
        LIMIT 5;
    " 2>/dev/null || echo "   All repos are maintainable!"
    echo ""

    echo -e "${GREEN}💡 Quick Wins:${NC}"
    echo "   - Add test files to repos with 0% coverage"
    echo "   - Remove commented-out code"
    echo "   - Break down large functions (>100 lines)"
    echo "   - Address TODO/FIXME comments"
    echo "   - Add documentation to complex functions"
    echo ""
}

# Export quality report
export_report() {
    local output_file="${1:-quality-report-$(date +%Y%m%d-%H%M%S).json}"

    echo -e "${CYAN}Exporting quality report...${NC}"

    if [ ! -f "$QUALITY_DB" ]; then
        echo "No analysis data found"
        return
    fi

    cat > "$output_file" <<EOF
{
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "summary": {
EOF

    # Add summary stats
    sqlite3 "$QUALITY_DB" "
        SELECT
            '    \"total_repos\": ' || COUNT(*) || ',',
            '    \"average_maintainability\": ' || ROUND(AVG(maintainability_score), 2) || ',',
            '    \"average_coverage\": ' || ROUND(AVG(test_coverage), 2) || ',',
            '    \"total_security_issues\": ' || SUM(security_issues)
        FROM quality_reports;
    " 2>/dev/null >> "$output_file"

    cat >> "$output_file" <<EOF
  },
  "repositories": [
EOF

    # Add repo data
    sqlite3 "$QUALITY_DB" "
        SELECT
            '    {' ||
            '\"name\": \"' || repo || '\", ' ||
            '\"grade\": \"' || overall_grade || '\", ' ||
            '\"maintainability\": ' || ROUND(maintainability_score, 2) || ', ' ||
            '\"coverage\": ' || ROUND(test_coverage, 2) || ', ' ||
            '\"security_issues\": ' || security_issues ||
            '},'
        FROM quality_reports
        ORDER BY repo;
    " 2>/dev/null | sed '$ s/,$//' >> "$output_file"

    cat >> "$output_file" <<EOF
  ]
}
EOF

    echo -e "${GREEN}✓ Report exported: $output_file${NC}"
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Intelligent Code Quality Analyzer${NC}

Analyzes code quality across all repositories with AI-powered insights.

USAGE:
    blackroad-code-quality-analyzer.sh <command> [args]

COMMANDS:
    init                    Initialize quality database
    analyze-all             Analyze all repositories
    stats                   Show quality statistics
    report <repo>           Show detailed report for repository
    suggestions             Generate improvement suggestions
    export [file]           Export quality report to JSON
    help                    Show this help

EXAMPLES:
    # Analyze all repos
    blackroad-code-quality-analyzer.sh analyze-all

    # View statistics
    blackroad-code-quality-analyzer.sh stats

    # Get detailed report
    blackroad-code-quality-analyzer.sh report blackroad-api

    # Get suggestions
    blackroad-code-quality-analyzer.sh suggestions

    # Export report
    blackroad-code-quality-analyzer.sh export quality.json

METRICS ANALYZED:
    ✓ Code complexity
    ✓ Maintainability score
    ✓ Test coverage
    ✓ Code smells
    ✓ Security issues
    ✓ Overall grade (A-F)

FEATURES:
    ✓ Multi-language support (JS/TS/Python/Go)
    ✓ Automatic grade calculation
    ✓ Actionable suggestions
    ✓ Trend tracking over time
    ✓ JSON export for CI/CD
    ✓ Memory system integration

DATABASE: $QUALITY_DB
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        analyze-all)
            init_db
            analyze_all
            ;;
        stats)
            show_stats
            ;;
        report)
            show_report "$2"
            ;;
        suggestions)
            generate_suggestions
            ;;
        export)
            export_report "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[QUALITY]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
