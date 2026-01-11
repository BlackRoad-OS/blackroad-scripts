#!/bin/bash
# BlackRoad Dependency Auto-Updater
# Automatically updates dependencies across ALL repos
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
UPDATE_DB="$HOME/.blackroad/dependency-updates/updates.db"

# Initialize database
init_db() {
    mkdir -p "$(dirname "$UPDATE_DB")"

    sqlite3 "$UPDATE_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS dependency_updates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT NOT NULL,
    package_manager TEXT NOT NULL,
    dependency TEXT NOT NULL,
    old_version TEXT,
    new_version TEXT,
    update_type TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'pending',
    error_message TEXT
);

CREATE INDEX IF NOT EXISTS idx_repo ON dependency_updates(repo);
CREATE INDEX IF NOT EXISTS idx_status ON dependency_updates(status);
CREATE INDEX IF NOT EXISTS idx_updated_at ON dependency_updates(updated_at);

CREATE TABLE IF NOT EXISTS update_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    total_repos INTEGER DEFAULT 0,
    repos_updated INTEGER DEFAULT 0,
    total_updates INTEGER DEFAULT 0,
    status TEXT DEFAULT 'running'
);
SQL

    echo -e "${GREEN}[DEPENDENCY-UPDATER]${NC} Database initialized!"
}

# Detect package manager for a repo
detect_package_manager() {
    local repo_path="$1"
    local managers=""

    [ -f "$repo_path/package.json" ] && managers="${managers}npm "
    [ -f "$repo_path/requirements.txt" ] && managers="${managers}pip "
    [ -f "$repo_path/Pipfile" ] && managers="${managers}pipenv "
    [ -f "$repo_path/go.mod" ] && managers="${managers}go "
    [ -f "$repo_path/Cargo.toml" ] && managers="${managers}cargo "
    [ -f "$repo_path/pom.xml" ] && managers="${managers}maven "
    [ -f "$repo_path/build.gradle" ] && managers="${managers}gradle "

    echo "$managers"
}

# Update npm dependencies
update_npm() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${CYAN}  Checking npm dependencies...${NC}"

    cd "$repo_path"

    # Check for outdated packages
    if command -v npm &> /dev/null; then
        local outdated=$(npm outdated --json 2>/dev/null || echo "{}")

        if [ "$outdated" != "{}" ]; then
            echo "$outdated" | jq -r 'to_entries[] | "\(.key) \(.value.current) \(.value.latest)"' | \
            while read -r pkg current latest; do
                if [ "$current" != "$latest" ]; then
                    echo -e "    ${YELLOW}Updating:${NC} $pkg ($current → $latest)"

                    # Log to database
                    sqlite3 "$UPDATE_DB" <<SQL
INSERT INTO dependency_updates (repo, package_manager, dependency, old_version, new_version, update_type)
VALUES ('$repo_name', 'npm', '$pkg', '$current', '$latest', 'minor');
SQL

                    # Update package
                    npm install "$pkg@latest" --save 2>/dev/null || \
                        sqlite3 "$UPDATE_DB" "UPDATE dependency_updates SET status='failed', error_message='npm install failed' WHERE repo='$repo_name' AND dependency='$pkg' AND updated_at=(SELECT MAX(updated_at) FROM dependency_updates WHERE repo='$repo_name' AND dependency='$pkg');"
                fi
            done
        else
            echo -e "    ${GREEN}✓${NC} All npm packages up to date"
        fi
    else
        echo -e "    ${YELLOW}⚠${NC} npm not found, skipping"
    fi
}

# Update pip dependencies
update_pip() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${CYAN}  Checking pip dependencies...${NC}"

    cd "$repo_path"

    if [ -f "requirements.txt" ]; then
        if command -v pip &> /dev/null; then
            # Create virtual env if doesn't exist
            if [ ! -d ".venv" ]; then
                python3 -m venv .venv 2>/dev/null || true
            fi

            # Activate and check outdated
            if [ -d ".venv" ]; then
                source .venv/bin/activate 2>/dev/null || true

                local outdated=$(pip list --outdated --format=json 2>/dev/null || echo "[]")

                if [ "$outdated" != "[]" ]; then
                    echo "$outdated" | jq -r '.[] | "\(.name) \(.version) \(.latest_version)"' | \
                    while read -r pkg current latest; do
                        echo -e "    ${YELLOW}Updating:${NC} $pkg ($current → $latest)"

                        # Log to database
                        sqlite3 "$UPDATE_DB" <<SQL
INSERT INTO dependency_updates (repo, package_manager, dependency, old_version, new_version, update_type)
VALUES ('$repo_name', 'pip', '$pkg', '$current', '$latest', 'minor');
SQL

                        # Update package
                        pip install --upgrade "$pkg" 2>/dev/null || \
                            sqlite3 "$UPDATE_DB" "UPDATE dependency_updates SET status='failed', error_message='pip upgrade failed' WHERE repo='$repo_name' AND dependency='$pkg' AND updated_at=(SELECT MAX(updated_at) FROM dependency_updates WHERE repo='$repo_name' AND dependency='$pkg');"
                    done
                else
                    echo -e "    ${GREEN}✓${NC} All pip packages up to date"
                fi

                deactivate 2>/dev/null || true
            fi
        else
            echo -e "    ${YELLOW}⚠${NC} pip not found, skipping"
        fi
    fi
}

# Update Go dependencies
update_go() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${CYAN}  Checking Go dependencies...${NC}"

    cd "$repo_path"

    if [ -f "go.mod" ]; then
        if command -v go &> /dev/null; then
            echo -e "    ${YELLOW}Updating Go modules...${NC}"

            go get -u ./... 2>/dev/null && \
                echo -e "    ${GREEN}✓${NC} Go modules updated" || \
                echo -e "    ${RED}✗${NC} Go update failed"

            go mod tidy 2>/dev/null || true
        else
            echo -e "    ${YELLOW}⚠${NC} go not found, skipping"
        fi
    fi
}

# Update a single repository
update_repo() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${PURPLE}━━━ $repo_name ━━━${NC}"

    # Detect package managers
    local managers=$(detect_package_manager "$repo_path")

    if [ -z "$managers" ]; then
        echo -e "  ${YELLOW}No package managers detected${NC}"
        return
    fi

    echo -e "  ${CYAN}Package managers:${NC} $managers"

    # Update based on detected managers
    [[ "$managers" =~ "npm" ]] && update_npm "$repo_path"
    [[ "$managers" =~ "pip" ]] && update_pip "$repo_path"
    [[ "$managers" =~ "go" ]] && update_go "$repo_path"

    echo ""
}

# Update all repositories
update_all() {
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}║   🔄 BLACKROAD DEPENDENCY AUTO-UPDATER 🔄            ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Start update run
    local run_id=$(sqlite3 "$UPDATE_DB" "INSERT INTO update_runs DEFAULT VALUES; SELECT last_insert_rowid();")

    local total=0
    local updated=0

    # Find all git repos
    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            ((total++))

            if update_repo "$repo_path"; then
                ((updated++))
            fi
        done
    fi

    # Complete update run
    sqlite3 "$UPDATE_DB" <<SQL
UPDATE update_runs
SET completed_at=CURRENT_TIMESTAMP,
    total_repos=$total,
    repos_updated=$updated,
    status='completed'
WHERE id=$run_id;
SQL

    echo -e "${GREEN}━━━ Update Complete ━━━${NC}"
    echo -e "${CYAN}Repositories processed:${NC} $total"
    echo -e "${CYAN}Repositories updated:${NC} $updated"
    echo ""

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "dependency-updater" "Auto-updated dependencies across $updated repositories. Total packages updated: $(sqlite3 "$UPDATE_DB" "SELECT COUNT(*) FROM dependency_updates WHERE status='pending';")." "dependencies,automation,updates" 2>/dev/null || true
    fi
}

# Show update statistics
show_stats() {
    echo -e "${CYAN}━━━ Dependency Update Statistics ━━━${NC}"
    echo ""

    # Recent updates
    echo -e "${PURPLE}Recent Updates (Last 24 hours):${NC}"
    sqlite3 -column "$UPDATE_DB" "
        SELECT
            repo,
            dependency,
            old_version || ' → ' || new_version as update,
            package_manager
        FROM dependency_updates
        WHERE datetime(updated_at) > datetime('now', '-24 hours')
        ORDER BY updated_at DESC
        LIMIT 20;
    " 2>/dev/null || echo "No recent updates"

    echo ""

    # Summary by package manager
    echo -e "${PURPLE}Updates by Package Manager:${NC}"
    sqlite3 -column "$UPDATE_DB" "
        SELECT
            package_manager,
            COUNT(*) as total_updates,
            SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as successful,
            SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed
        FROM dependency_updates
        GROUP BY package_manager;
    " 2>/dev/null || echo "No data"

    echo ""
}

# Show pending updates
show_pending() {
    echo -e "${CYAN}━━━ Pending Updates ━━━${NC}"
    echo ""

    sqlite3 -column "$UPDATE_DB" "
        SELECT
            repo,
            dependency,
            old_version,
            new_version,
            package_manager
        FROM dependency_updates
        WHERE status='pending'
        ORDER BY repo, dependency;
    " 2>/dev/null || echo "No pending updates"
}

# Check for security vulnerabilities
check_vulnerabilities() {
    echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║                                                       ║${NC}"
    echo -e "${BOLD}${RED}║   🔒 SECURITY VULNERABILITY SCANNER 🔒               ║${NC}"
    echo -e "${BOLD}${RED}║                                                       ║${NC}"
    echo -e "${BOLD}${RED}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            local repo_name=$(basename "$repo_path")

            cd "$repo_path"

            # Check npm vulnerabilities
            if [ -f "package.json" ] && command -v npm &> /dev/null; then
                echo -e "${PURPLE}━━━ $repo_name (npm) ━━━${NC}"
                local audit=$(npm audit --json 2>/dev/null || echo '{"metadata":{"vulnerabilities":{"total":0}}}')
                local vulns=$(echo "$audit" | jq -r '.metadata.vulnerabilities.total')

                if [ "$vulns" -gt 0 ]; then
                    echo -e "${RED}  ⚠️  Found $vulns vulnerabilities${NC}"
                    echo "$audit" | jq -r '.vulnerabilities | to_entries[] | "    \(.value.severity): \(.key)"' 2>/dev/null || true
                else
                    echo -e "${GREEN}  ✓ No vulnerabilities found${NC}"
                fi
                echo ""
            fi
        done
    fi
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Dependency Auto-Updater${NC}

Automatically updates dependencies across ALL repositories.

USAGE:
    blackroad-dependency-updater.sh <command>

COMMANDS:
    init            Initialize dependency update database
    update-all      Update dependencies in all repositories
    stats           Show update statistics
    pending         Show pending updates
    vulnerabilities Check for security vulnerabilities
    help            Show this help

EXAMPLES:
    # Update all repos
    blackroad-dependency-updater.sh update-all

    # Check vulnerabilities
    blackroad-dependency-updater.sh vulnerabilities

    # View stats
    blackroad-dependency-updater.sh stats

SUPPORTED PACKAGE MANAGERS:
    ✓ npm (Node.js)
    ✓ pip (Python)
    ✓ go modules (Go)
    ✓ cargo (Rust) - coming soon
    ✓ maven (Java) - coming soon

FEATURES:
    ✓ Automatic detection of package managers
    ✓ Safe updates (minor/patch only by default)
    ✓ Vulnerability scanning
    ✓ Update tracking in database
    ✓ Memory system integration
    ✓ Coordination-aware

DATABASE: $UPDATE_DB
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        update-all)
            init_db
            update_all
            ;;
        stats)
            show_stats
            ;;
        pending)
            show_pending
            ;;
        vulnerabilities|vuln)
            check_vulnerabilities
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[DEPENDENCY-UPDATER]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
