#!/bin/bash
#
# BlackRoad Progress - Complete Infrastructure Metrics
#
# Indexes and quantifies EVERYTHING across the entire BlackRoad ecosystem.
# Shows real-time progress, statistics, and health metrics.
#
# Usage:
#   blackroad-progress              # Show full dashboard
#   blackroad-progress stats        # Quick stats only
#   blackroad-progress index        # Re-index everything
#   blackroad-progress watch        # Live updates
#   blackroad-progress export       # Export to JSON
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration
PROGRESS_DB="$HOME/.blackroad-progress.db"
CACHE_DIR="$HOME/.blackroad-progress-cache"
INDEX_TIMESTAMP="$CACHE_DIR/last-index.txt"

# Initialize database
init_db() {
    mkdir -p "$CACHE_DIR"

    if [ ! -f "$PROGRESS_DB" ]; then
        sqlite3 "$PROGRESS_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS repositories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    org TEXT NOT NULL,
    name TEXT NOT NULL,
    full_name TEXT NOT NULL,
    url TEXT,
    size_kb INTEGER,
    created_at TEXT,
    updated_at TEXT,
    primary_language TEXT,
    is_private INTEGER,
    is_fork INTEGER,
    indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(org, name)
);

CREATE TABLE IF NOT EXISTS files (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER,
    file_path TEXT NOT NULL,
    file_type TEXT,
    size_bytes INTEGER,
    lines INTEGER,
    language TEXT,
    is_binary INTEGER DEFAULT 0,
    indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (repo_id) REFERENCES repositories(id)
);

CREATE TABLE IF NOT EXISTS statistics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    metric_name TEXT NOT NULL,
    metric_value TEXT NOT NULL,
    category TEXT,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS scripts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    script_name TEXT NOT NULL,
    script_path TEXT,
    lines INTEGER,
    size_bytes INTEGER,
    functions_count INTEGER,
    description TEXT,
    category TEXT,
    indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(script_name)
);

CREATE INDEX IF NOT EXISTS idx_files_repo ON files(repo_id);
CREATE INDEX IF NOT EXISTS idx_files_type ON files(file_type);
CREATE INDEX IF NOT EXISTS idx_stats_category ON statistics(category);
EOF
        echo "✅ Database initialized at $PROGRESS_DB"
    fi
}

# Index all GitHub repositories
index_repositories() {
    echo -e "${CYAN}📦 Indexing GitHub Repositories...${NC}"

    orgs=(
        "BlackRoad-OS"
        "BlackRoad-AI"
        "BlackRoad-Archive"
        "BlackRoad-Cloud"
        "BlackRoad-Education"
        "BlackRoad-Foundation"
        "BlackRoad-Gov"
        "BlackRoad-Hardware"
        "BlackRoad-Interactive"
        "BlackRoad-Labs"
        "BlackRoad-Media"
        "BlackRoad-Security"
        "BlackRoad-Studio"
        "BlackRoad-Ventures"
        "Blackbox-Enterprises"
    )

    total_repos=0

    for org in "${orgs[@]}"; do
        echo "  Indexing $org..."

        repos=$(gh repo list "$org" --limit 1000 --json nameWithOwner,name,url,diskUsage,createdAt,updatedAt,primaryLanguage,isPrivate,isFork 2>/dev/null || echo "[]")

        if [ "$repos" = "[]" ] || [ -z "$repos" ]; then
            continue
        fi

        # Parse and insert into database
        echo "$repos" | jq -r '.[] | [.nameWithOwner, .name, .url, .diskUsage, .createdAt, .updatedAt, (.primaryLanguage.name // "Unknown"), (.isPrivate | if . then 1 else 0 end), (.isFork | if . then 1 else 0 end)] | @tsv' | while IFS=$'\t' read -r full_name name url size created updated lang private fork; do
            sqlite3 "$PROGRESS_DB" << SQL
INSERT OR REPLACE INTO repositories (org, name, full_name, url, size_kb, created_at, updated_at, primary_language, is_private, is_fork)
VALUES ('$org', '$name', '$full_name', '$url', $size, '$created', '$updated', '$lang', $private, $fork);
SQL
            ((total_repos++)) || true
        done
    done

    echo -e "${GREEN}✅ Indexed $total_repos repositories${NC}"

    # Save statistics
    sqlite3 "$PROGRESS_DB" "INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_repos', '$total_repos', 'github');"
}

# Index local files in key repositories
index_local_files() {
    echo -e "${CYAN}📁 Indexing Local Files...${NC}"

    local_repos=(
        "$HOME/projects/blackroad-os-operator"
        "$HOME/projects/blackroad-os-core"
        "$HOME/projects/blackroad-os-agents"
        "$HOME/projects/blackroad-deployment-docs"
        "$HOME/blackroad-backup"
    )

    total_files=0
    total_lines=0

    for repo_path in "${local_repos[@]}"; do
        if [ ! -d "$repo_path" ]; then
            continue
        fi

        repo_name=$(basename "$repo_path")
        echo "  Indexing $repo_name..."

        # Get repo ID from database
        repo_id=$(sqlite3 "$PROGRESS_DB" "SELECT id FROM repositories WHERE name='$repo_name' LIMIT 1;" 2>/dev/null || echo "")

        if [ -z "$repo_id" ]; then
            # Create repo entry if doesn't exist
            sqlite3 "$PROGRESS_DB" "INSERT INTO repositories (org, name, full_name, url) VALUES ('local', '$repo_name', '$repo_name', '$repo_path');"
            repo_id=$(sqlite3 "$PROGRESS_DB" "SELECT id FROM repositories WHERE name='$repo_name' LIMIT 1;")
        fi

        # Index all files
        find "$repo_path" -type f ! -path "*/\.*" ! -path "*/node_modules/*" ! -path "*/venv/*" ! -path "*/__pycache__/*" 2>/dev/null | while read -r file; do
            rel_path="${file#$repo_path/}"
            ext="${file##*.}"
            size=$(wc -c < "$file" 2>/dev/null || echo "0")
            lines=$(wc -l < "$file" 2>/dev/null || echo "0")

            # Detect language by extension
            case "$ext" in
                py) lang="Python" ;;
                js) lang="JavaScript" ;;
                ts) lang="TypeScript" ;;
                sh) lang="Shell" ;;
                html) lang="HTML" ;;
                css) lang="CSS" ;;
                md) lang="Markdown" ;;
                json) lang="JSON" ;;
                yaml|yml) lang="YAML" ;;
                *) lang="Unknown" ;;
            esac

            # Check if binary
            is_binary=0
            if file "$file" | grep -q "binary"; then
                is_binary=1
            fi

            sqlite3 "$PROGRESS_DB" << SQL
INSERT OR REPLACE INTO files (repo_id, file_path, file_type, size_bytes, lines, language, is_binary)
VALUES ($repo_id, '$rel_path', '$ext', $size, $lines, '$lang', $is_binary);
SQL

            ((total_files++)) || true
            total_lines=$((total_lines + lines))
        done
    done

    echo -e "${GREEN}✅ Indexed $total_files files ($total_lines lines)${NC}"

    sqlite3 "$PROGRESS_DB" "INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_files', '$total_files', 'local');"
    sqlite3 "$PROGRESS_DB" "INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_lines', '$total_lines', 'local');"
}

# Index all automation scripts
index_scripts() {
    echo -e "${CYAN}🔧 Indexing Automation Scripts...${NC}"

    total_scripts=0
    total_script_lines=0

    find ~ -maxdepth 1 -type f -name "*.sh" ! -name ".*" 2>/dev/null | sort | while read -r script; do
        name=$(basename "$script")
        size=$(wc -c < "$script" 2>/dev/null || echo "0")
        lines=$(wc -l < "$script" 2>/dev/null || echo "0")

        # Count functions
        funcs=$(grep -cE "^(function |[a-zA-Z_][a-zA-Z0-9_]*\(\))" "$script" 2>/dev/null || echo "0")

        # Get description (first few comment lines)
        desc=$(grep -E "^#" "$script" | head -3 | tail -2 | sed 's/^# *//' | tr '\n' ' ' | cut -c1-200)

        # Categorize by name prefix
        category="other"
        case "$name" in
            memory-*) category="memory" ;;
            blackroad-*) category="blackroad" ;;
            claude-*) category="claude" ;;
            deploy-*) category="deployment" ;;
            setup-*) category="setup" ;;
            test-*) category="testing" ;;
            greenlight-*) category="greenlight" ;;
            trinity-*) category="trinity" ;;
        esac

        sqlite3 "$PROGRESS_DB" << SQL
INSERT OR REPLACE INTO scripts (script_name, script_path, lines, size_bytes, functions_count, description, category)
VALUES ('$name', '$script', $lines, $size, $funcs, '$desc', '$category');
SQL

        ((total_scripts++)) || true
        total_script_lines=$((total_script_lines + lines))
    done

    echo -e "${GREEN}✅ Indexed $total_scripts scripts ($total_script_lines lines)${NC}"

    sqlite3 "$PROGRESS_DB" "INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_scripts', '$total_scripts', 'scripts');"
    sqlite3 "$PROGRESS_DB" "INSERT INTO statistics (metric_name, metric_value, category) VALUES ('script_lines', '$total_script_lines', 'scripts');"
}

# Calculate comprehensive statistics
calculate_statistics() {
    echo -e "${CYAN}📊 Calculating Statistics...${NC}"

    # Repository statistics
    total_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories;")
    public_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories WHERE is_private=0;")
    private_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories WHERE is_private=1;")
    total_size_kb=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(size_kb) FROM repositories;")
    total_size_mb=$((total_size_kb / 1024))

    # File statistics
    total_files=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM files;")
    total_lines=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM files WHERE is_binary=0;")

    # Script statistics
    total_scripts=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM scripts;")
    script_lines=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM scripts;")

    # Language breakdown
    echo -e "${GREEN}✅ Statistics calculated${NC}"

    # Save to statistics table
    sqlite3 "$PROGRESS_DB" << SQL
DELETE FROM statistics WHERE category='calculated';
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_repos', '$total_repos', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('public_repos', '$public_repos', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('private_repos', '$private_repos', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_size_mb', '$total_size_mb', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_files', '$total_files', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_lines', '$total_lines', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('total_scripts', '$total_scripts', 'calculated');
INSERT INTO statistics (metric_name, metric_value, category) VALUES ('script_lines', '$script_lines', 'calculated');
SQL

    # Save timestamp
    date +%s > "$INDEX_TIMESTAMP"
}

# Display dashboard
show_dashboard() {
    echo -e "${WHITE}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                    ║"
    echo "║         🌌 BLACKROAD PROGRESS - COMPLETE INFRASTRUCTURE 🌌         ║"
    echo "║                                                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check if indexed
    if [ ! -f "$PROGRESS_DB" ]; then
        echo -e "${YELLOW}⚠️  No data indexed yet. Run: blackroad-progress index${NC}"
        return
    fi

    # Show last index time
    if [ -f "$INDEX_TIMESTAMP" ]; then
        last_index=$(cat "$INDEX_TIMESTAMP")
        last_index_date=$(date -r "$last_index" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
        echo -e "${CYAN}Last indexed: $last_index_date${NC}"
        echo ""
    fi

    # GitHub Repositories
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}📦 GITHUB REPOSITORIES${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    total_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories;")
    public_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories WHERE is_private=0;")
    private_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories WHERE is_private=1;")
    total_size_kb=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(size_kb) FROM repositories;" | awk '{print int($1)}')
    total_size_mb=$((total_size_kb / 1024))

    echo "  Total Repositories: $total_repos"
    echo "  Public: $public_repos | Private: $private_repos"
    echo "  Total Size: ${total_size_mb} MB (${total_size_kb} KB)"
    echo ""

    # Top 10 repositories by size
    echo "  📊 Top 10 Largest Repositories:"
    sqlite3 "$PROGRESS_DB" "SELECT name, size_kb/1024 || ' MB', primary_language FROM repositories ORDER BY size_kb DESC LIMIT 10;" | while IFS='|' read -r name size lang; do
        printf "    %-40s %10s  %s\n" "$name" "$size" "$lang"
    done
    echo ""

    # Language breakdown
    echo "  🔤 Language Breakdown:"
    sqlite3 "$PROGRESS_DB" "SELECT primary_language, COUNT(*) FROM repositories GROUP BY primary_language ORDER BY COUNT(*) DESC LIMIT 10;" | while IFS='|' read -r lang count; do
        printf "    %-20s %s repos\n" "$lang" "$count"
    done
    echo ""

    # Files
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📁 FILES (Local Repositories)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    total_files=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM files;")
    total_lines=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM files WHERE is_binary=0;" | awk '{print int($1)}')
    total_bytes=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(size_bytes) FROM files;" | awk '{print int($1)}')
    total_mb=$((total_bytes / 1024 / 1024))

    echo "  Total Files: $total_files"
    echo "  Total Lines: $total_lines"
    echo "  Total Size: ${total_mb} MB"
    echo ""

    # File types
    echo "  📄 File Types:"
    sqlite3 "$PROGRESS_DB" "SELECT file_type, COUNT(*) FROM files GROUP BY file_type ORDER BY COUNT(*) DESC LIMIT 15;" | while IFS='|' read -r type count; do
        printf "    %-20s %s files\n" "$type" "$count"
    done
    echo ""

    # Language breakdown for files
    echo "  🔤 Files by Language:"
    sqlite3 "$PROGRESS_DB" "SELECT language, COUNT(*), SUM(lines) FROM files WHERE is_binary=0 GROUP BY language ORDER BY SUM(lines) DESC LIMIT 10;" | while IFS='|' read -r lang count lines; do
        printf "    %-20s %6s files, %10s lines\n" "$lang" "$count" "$lines"
    done
    echo ""

    # Automation Scripts
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🔧 AUTOMATION SCRIPTS${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    total_scripts=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM scripts;")
    script_lines=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM scripts;" | awk '{print int($1)}')
    total_funcs=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(functions_count) FROM scripts;" | awk '{print int($1)}')

    echo "  Total Scripts: $total_scripts"
    echo "  Total Lines: $script_lines"
    echo "  Total Functions: $total_funcs"
    echo ""

    # Scripts by category
    echo "  📊 Scripts by Category:"
    sqlite3 "$PROGRESS_DB" "SELECT category, COUNT(*), SUM(lines) FROM scripts GROUP BY category ORDER BY SUM(lines) DESC;" | while IFS='|' read -r cat count lines; do
        printf "    %-20s %3s scripts, %6s lines\n" "$cat" "$count" "$lines"
    done
    echo ""

    # Top scripts by size
    echo "  📈 Top 10 Largest Scripts:"
    sqlite3 "$PROGRESS_DB" "SELECT script_name, lines, functions_count FROM scripts ORDER BY lines DESC LIMIT 10;" | while IFS='|' read -r name lines funcs; do
        printf "    %-50s %5s lines, %3s functions\n" "$name" "$lines" "$funcs"
    done
    echo ""

    # Overall Summary
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 OVERALL SUMMARY${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    total_code_lines=$((total_lines + script_lines))

    echo "  GitHub Repositories: $total_repos ($public_repos public, $private_repos private)"
    echo "  Total Codebase Size: $total_size_mb MB"
    echo "  Local Files Indexed: $total_files"
    echo "  Total Lines of Code: $total_code_lines"
    echo "  Automation Scripts: $total_scripts ($script_lines lines, $total_funcs functions)"
    echo ""
    echo -e "${CYAN}💡 Run 'blackroad-progress index' to refresh data${NC}"
    echo -e "${CYAN}💡 Run 'blackroad-progress export' to export as JSON${NC}"
    echo ""
}

# Quick stats
show_stats() {
    if [ ! -f "$PROGRESS_DB" ]; then
        echo "No data. Run: blackroad-progress index"
        return
    fi

    total_repos=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories;")
    total_size_mb=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(size_kb)/1024 FROM repositories;" | awk '{print int($1)}')
    total_files=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM files;")
    total_lines=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM files WHERE is_binary=0;" | awk '{print int($1)}')
    total_scripts=$(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM scripts;")
    script_lines=$(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM scripts;" | awk '{print int($1)}')

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌌 BLACKROAD PROGRESS - QUICK STATS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Repositories: $total_repos"
    echo "  Size: $total_size_mb MB"
    echo "  Files: $total_files"
    echo "  Lines: $total_lines"
    echo "  Scripts: $total_scripts ($script_lines lines)"
    echo "  Total Code: $((total_lines + script_lines)) lines"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Export to JSON
export_json() {
    if [ ! -f "$PROGRESS_DB" ]; then
        echo "No data. Run: blackroad-progress index"
        return
    fi

    output_file="${1:-$HOME/blackroad-progress.json}"

    echo -e "${CYAN}Exporting to $output_file...${NC}"

    cat > "$output_file" << EOF
{
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "repositories": {
    "total": $(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories;"),
    "public": $(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories WHERE is_private=0;"),
    "private": $(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM repositories WHERE is_private=1;"),
    "total_size_mb": $(sqlite3 "$PROGRESS_DB" "SELECT SUM(size_kb)/1024 FROM repositories;" | awk '{print int($1)}')
  },
  "files": {
    "total": $(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM files;"),
    "lines": $(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM files WHERE is_binary=0;" | awk '{print int($1)}'),
    "size_mb": $(sqlite3 "$PROGRESS_DB" "SELECT SUM(size_bytes)/1024/1024 FROM files;" | awk '{print int($1)}')
  },
  "scripts": {
    "total": $(sqlite3 "$PROGRESS_DB" "SELECT COUNT(*) FROM scripts;"),
    "lines": $(sqlite3 "$PROGRESS_DB" "SELECT SUM(lines) FROM scripts;" | awk '{print int($1)}'),
    "functions": $(sqlite3 "$PROGRESS_DB" "SELECT SUM(functions_count) FROM scripts;" | awk '{print int($1)}')
  }
}
EOF

    echo -e "${GREEN}✅ Exported to $output_file${NC}"
}

# Watch mode
watch_mode() {
    while true; do
        clear
        show_dashboard
        echo -e "${CYAN}Refreshing in 10 seconds... (Ctrl+C to exit)${NC}"
        sleep 10
    done
}

# Full index
full_index() {
    echo -e "${WHITE}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║         🌌 BLACKROAD PROGRESS - FULL INDEX                         ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    init_db
    index_repositories
    index_local_files
    index_scripts
    calculate_statistics

    echo ""
    echo -e "${GREEN}✅ Indexing complete!${NC}"
    echo ""
    echo "Run 'blackroad-progress' to see the dashboard"
}

# Help
show_help() {
    cat << EOF
BlackRoad Progress - Complete Infrastructure Metrics

Usage:
  blackroad-progress              Show full dashboard
  blackroad-progress stats        Quick stats only
  blackroad-progress index        Re-index everything
  blackroad-progress watch        Live updates (10s refresh)
  blackroad-progress export [file] Export to JSON
  blackroad-progress help         Show this help

Examples:
  blackroad-progress
  blackroad-progress index
  blackroad-progress export ~/progress.json
  blackroad-progress watch

The index command will:
  • Scan all 15 GitHub organizations
  • Index all repositories and metadata
  • Analyze local repository files
  • Index all automation scripts
  • Calculate comprehensive statistics

Data stored in: $PROGRESS_DB
EOF
}

# Main
case "${1:-dashboard}" in
    stats)
        show_stats
        ;;
    index)
        full_index
        ;;
    watch)
        watch_mode
        ;;
    export)
        export_json "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    dashboard|*)
        show_dashboard
        ;;
esac
