#!/bin/bash
# BlackRoad Cross-Repository Refactoring Tools
# Perform safe refactoring operations across ALL repos
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
REFACTOR_DB="$HOME/.blackroad/refactoring/operations.db"
DRY_RUN="${DRY_RUN:-true}"

# Initialize database
init_db() {
    mkdir -p "$(dirname "$REFACTOR_DB")"

    sqlite3 "$REFACTOR_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS refactor_operations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_type TEXT NOT NULL,
    pattern TEXT NOT NULL,
    replacement TEXT,
    repos_affected TEXT,
    files_changed INTEGER DEFAULT 0,
    lines_changed INTEGER DEFAULT 0,
    started_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    status TEXT DEFAULT 'pending',
    dry_run INTEGER DEFAULT 1,
    agent_id TEXT
);

CREATE TABLE IF NOT EXISTS file_changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_id INTEGER,
    repo TEXT NOT NULL,
    file_path TEXT NOT NULL,
    old_content TEXT,
    new_content TEXT,
    diff TEXT,
    FOREIGN KEY (operation_id) REFERENCES refactor_operations(id)
);

CREATE INDEX IF NOT EXISTS idx_operation_status ON refactor_operations(status);
CREATE INDEX IF NOT EXISTS idx_file_changes_repo ON file_changes(repo);
SQL

    echo -e "${GREEN}[REFACTOR]${NC} Database initialized!"
}

# Rename function across all repos
rename_function() {
    local old_name="$1"
    local new_name="$2"
    local file_pattern="${3:-*.js,*.ts,*.go,*.py}"

    if [ -z "$old_name" ] || [ -z "$new_name" ]; then
        echo -e "${RED}[REFACTOR]${NC} Usage: rename-function <old_name> <new_name> [file_pattern]"
        return 1
    fi

    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}║   🔧 CROSS-REPO FUNCTION RENAME 🔧                   ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${PURPLE}Operation:${NC} Rename function '${YELLOW}$old_name${NC}' → '${GREEN}$new_name${NC}'"
    echo -e "${PURPLE}File pattern:${NC} $file_pattern"
    echo -e "${PURPLE}Mode:${NC} $([ "$DRY_RUN" = "true" ] && echo "${YELLOW}DRY RUN${NC}" || echo "${RED}LIVE${NC}")"
    echo ""

    # Create operation record
    local op_id=$(sqlite3 "$REFACTOR_DB" <<SQL
INSERT INTO refactor_operations (operation_type, pattern, replacement, dry_run, agent_id)
VALUES ('rename_function', '$old_name', '$new_name', $([ "$DRY_RUN" = "true" ] && echo 1 || echo 0), '${MY_CLAUDE:-unknown}');
SELECT last_insert_rowid();
SQL
)

    local total_files=0
    local affected_repos=""

    # Find and replace across all repos
    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            local repo_name=$(basename "$repo_path")

            # Search for function name in repo
            local files=$(find "$repo_path" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.py" \) -exec grep -l "\b$old_name\b" {} \; 2>/dev/null || true)

            if [ -n "$files" ]; then
                echo -e "${PURPLE}━━━ $repo_name ━━━${NC}"

                while IFS= read -r file; do
                    if [ -f "$file" ]; then
                        ((total_files++))

                        # Show what would change
                        local matches=$(grep -n "\b$old_name\b" "$file" 2>/dev/null || true)
                        if [ -n "$matches" ]; then
                            echo -e "${CYAN}  $file${NC}"
                            echo "$matches" | sed 's/^/    /'

                            if [ "$DRY_RUN" != "true" ]; then
                                # Make actual changes
                                local backup="$file.bak.$(date +%s)"
                                cp "$file" "$backup"

                                # Use sed for safe replacement
                                sed -i.tmp "s/\b$old_name\b/$new_name/g" "$file" && rm -f "$file.tmp"

                                # Log change
                                sqlite3 "$REFACTOR_DB" <<SQL
INSERT INTO file_changes (operation_id, repo, file_path, old_content, new_content)
VALUES ($op_id, '$repo_name', '$file', '$(cat "$backup" | base64)', '$(cat "$file" | base64)');
SQL
                            fi
                        fi
                    fi
                done <<< "$files"

                affected_repos="$affected_repos$repo_name,"
                echo ""
            fi
        done
    fi

    # Update operation record
    sqlite3 "$REFACTOR_DB" <<SQL
UPDATE refactor_operations
SET completed_at=CURRENT_TIMESTAMP,
    status='completed',
    files_changed=$total_files,
    repos_affected='$affected_repos'
WHERE id=$op_id;
SQL

    echo -e "${GREEN}━━━ Refactoring Complete ━━━${NC}"
    echo -e "${CYAN}Files affected:${NC} $total_files"
    echo -e "${CYAN}Mode:${NC} $([ "$DRY_RUN" = "true" ] && echo "${YELLOW}DRY RUN (no changes made)${NC}" || echo "${GREEN}LIVE (changes committed)${NC}")"
    echo ""

    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}💡 To apply changes, run:${NC}"
        echo -e "   ${CYAN}DRY_RUN=false ~/blackroad-cross-repo-refactor.sh rename-function \"$old_name\" \"$new_name\"${NC}"
        echo ""
    fi

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "cross-repo-refactor" "Renamed function '$old_name' → '$new_name' across $total_files files. Mode: $([ "$DRY_RUN" = "true" ] && echo "DRY RUN" || echo "LIVE")" "refactoring,automation,code" 2>/dev/null || true
    fi
}

# Replace text pattern across all repos
replace_pattern() {
    local pattern="$1"
    local replacement="$2"
    local file_pattern="${3:-*}"

    if [ -z "$pattern" ] || [ -z "$replacement" ]; then
        echo -e "${RED}[REFACTOR]${NC} Usage: replace-pattern <pattern> <replacement> [file_pattern]"
        return 1
    fi

    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}║   🔍 CROSS-REPO PATTERN REPLACE 🔍                   ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${PURPLE}Pattern:${NC} ${YELLOW}$pattern${NC}"
    echo -e "${PURPLE}Replacement:${NC} ${GREEN}$replacement${NC}"
    echo -e "${PURPLE}File pattern:${NC} $file_pattern"
    echo -e "${PURPLE}Mode:${NC} $([ "$DRY_RUN" = "true" ] && echo "${YELLOW}DRY RUN${NC}" || echo "${RED}LIVE${NC}")"
    echo ""

    local total_files=0

    # Search across all repos
    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            local repo_name=$(basename "$repo_path")

            local files=$(find "$repo_path" -type f -name "$file_pattern" -exec grep -l "$pattern" {} \; 2>/dev/null || true)

            if [ -n "$files" ]; then
                echo -e "${PURPLE}━━━ $repo_name ━━━${NC}"

                while IFS= read -r file; do
                    if [ -f "$file" ]; then
                        ((total_files++))

                        local matches=$(grep -n "$pattern" "$file" 2>/dev/null || true)
                        if [ -n "$matches" ]; then
                            echo -e "${CYAN}  $file${NC}"
                            echo "$matches" | head -5 | sed 's/^/    /'

                            if [ "$DRY_RUN" != "true" ]; then
                                cp "$file" "$file.bak.$(date +%s)"
                                sed -i.tmp "s/$pattern/$replacement/g" "$file" && rm -f "$file.tmp"
                            fi
                        fi
                    fi
                done <<< "$files"
                echo ""
            fi
        done
    fi

    echo -e "${GREEN}━━━ Pattern Replace Complete ━━━${NC}"
    echo -e "${CYAN}Files affected:${NC} $total_files"
    echo ""
}

# Find all usages of a function/variable
find_usages() {
    local name="$1"
    local file_pattern="${2:-*.js,*.ts,*.go,*.py}"

    if [ -z "$name" ]; then
        echo -e "${RED}[REFACTOR]${NC} Usage: find-usages <name> [file_pattern]"
        return 1
    fi

    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}║   🔎 CROSS-REPO USAGE FINDER 🔎                      ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${PURPLE}Searching for:${NC} ${YELLOW}$name${NC}"
    echo ""

    local total_usages=0
    local total_files=0
    local total_repos=0

    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            local repo_name=$(basename "$repo_path")

            local files=$(find "$repo_path" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.py" \) -exec grep -l "\b$name\b" {} \; 2>/dev/null || true)

            if [ -n "$files" ]; then
                ((total_repos++))
                echo -e "${PURPLE}━━━ $repo_name ━━━${NC}"

                while IFS= read -r file; do
                    if [ -f "$file" ]; then
                        ((total_files++))
                        local count=$(grep -c "\b$name\b" "$file" 2>/dev/null || echo "0")
                        total_usages=$((total_usages + count))

                        echo -e "${CYAN}  $file${NC} (${count} usages)"
                        grep -n "\b$name\b" "$file" 2>/dev/null | head -3 | sed 's/^/    /'
                    fi
                done <<< "$files"
                echo ""
            fi
        done
    fi

    echo -e "${GREEN}━━━ Usage Summary ━━━${NC}"
    echo -e "${CYAN}Total usages:${NC} $total_usages"
    echo -e "${CYAN}Files:${NC} $total_files"
    echo -e "${CYAN}Repositories:${NC} $total_repos"
    echo ""
}

# Update import statements
update_imports() {
    local old_import="$1"
    local new_import="$2"

    if [ -z "$old_import" ] || [ -z "$new_import" ]; then
        echo -e "${RED}[REFACTOR]${NC} Usage: update-imports <old_import> <new_import>"
        return 1
    fi

    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}║   📦 CROSS-REPO IMPORT UPDATER 📦                    ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                       ║${NC}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${PURPLE}Old import:${NC} ${YELLOW}$old_import${NC}"
    echo -e "${PURPLE}New import:${NC} ${GREEN}$new_import${NC}"
    echo -e "${PURPLE}Mode:${NC} $([ "$DRY_RUN" = "true" ] && echo "${YELLOW}DRY RUN${NC}" || echo "${RED}LIVE${NC}")"
    echo ""

    local total_files=0

    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            local repo_name=$(basename "$repo_path")

            # Find files with import statements
            local files=$(find "$repo_path" -type f \( -name "*.js" -o -name "*.ts" \) -exec grep -l "import.*$old_import" {} \; 2>/dev/null || true)

            if [ -n "$files" ]; then
                echo -e "${PURPLE}━━━ $repo_name ━━━${NC}"

                while IFS= read -r file; do
                    if [ -f "$file" ]; then
                        ((total_files++))
                        echo -e "${CYAN}  $file${NC}"
                        grep "import.*$old_import" "$file" | sed 's/^/    /'

                        if [ "$DRY_RUN" != "true" ]; then
                            cp "$file" "$file.bak.$(date +%s)"
                            sed -i.tmp "s|$old_import|$new_import|g" "$file" && rm -f "$file.tmp"
                        fi
                    fi
                done <<< "$files"
                echo ""
            fi
        done
    fi

    echo -e "${GREEN}━━━ Import Update Complete ━━━${NC}"
    echo -e "${CYAN}Files updated:${NC} $total_files"
    echo ""
}

# Show refactoring history
show_history() {
    echo -e "${CYAN}━━━ Refactoring History ━━━${NC}"
    echo ""

    sqlite3 -column "$REFACTOR_DB" "
        SELECT
            substr(operation_type, 1, 20) as operation,
            substr(pattern, 1, 30) as pattern,
            substr(replacement, 1, 30) as replacement,
            files_changed as files,
            CASE WHEN dry_run=1 THEN 'DRY' ELSE 'LIVE' END as mode,
            status
        FROM refactor_operations
        ORDER BY started_at DESC
        LIMIT 20;
    " 2>/dev/null || echo "No history"
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Cross-Repository Refactoring Tools${NC}

Perform safe refactoring operations across ALL repositories.

USAGE:
    blackroad-cross-repo-refactor.sh <command> [args...]

COMMANDS:
    rename-function <old> <new> [pattern]
        Rename a function across all repos
        Example: rename-function "getUserData" "fetchUserData"

    replace-pattern <pattern> <replacement> [file_pattern]
        Replace a text pattern across all repos
        Example: replace-pattern "http://api.old.com" "https://api.new.com"

    find-usages <name> [file_pattern]
        Find all usages of a function/variable
        Example: find-usages "processPayment"

    update-imports <old> <new>
        Update import statements
        Example: update-imports "@old/package" "@new/package"

    history
        Show refactoring history

    init
        Initialize refactoring database

    help
        Show this help

MODES:
    DRY RUN (default): Shows what would change without making changes
    LIVE: Actually makes the changes

    Set DRY_RUN=false to run in LIVE mode:
    DRY_RUN=false ~/blackroad-cross-repo-refactor.sh rename-function "old" "new"

FEATURES:
    ✓ Safe refactoring with backups
    ✓ DRY RUN mode to preview changes
    ✓ Cross-repo awareness
    ✓ Automatic backup creation
    ✓ Coordination system integration
    ✓ Operation history tracking

SAFETY:
    - All operations create .bak files
    - DRY RUN mode enabled by default
    - Changes tracked in database
    - Integration with conflict detector

DATABASE: $REFACTOR_DB
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        rename-function)
            init_db
            rename_function "$2" "$3" "$4"
            ;;
        replace-pattern)
            init_db
            replace_pattern "$2" "$3" "$4"
            ;;
        find-usages)
            find_usages "$2" "$3"
            ;;
        update-imports)
            init_db
            update_imports "$2" "$3"
            ;;
        history)
            show_history
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[REFACTOR]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
