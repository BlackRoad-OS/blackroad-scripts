#!/bin/bash
# BlackRoad Progress - Complete Infrastructure Metrics
# Simplified version with better error handling

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

PROGRESS_DIR="$HOME/.blackroad-progress"
REPOS_FILE="$PROGRESS_DIR/repos.txt"
FILES_FILE="$PROGRESS_DIR/files.txt"
SCRIPTS_FILE="$PROGRESS_DIR/scripts.txt"
STATS_FILE="$PROGRESS_DIR/stats.json"

mkdir -p "$PROGRESS_DIR"

# Index GitHub repos
index_repos() {
    echo -e "${CYAN}📦 Indexing GitHub Repositories...${NC}"
    
    orgs="BlackRoad-OS BlackRoad-AI"
    
    > "$REPOS_FILE"
    total=0
    
    for org in $orgs; do
        echo "  Scanning $org..."
        gh repo list "$org" --limit 100 --json nameWithOwner,diskUsage,primaryLanguage,isPrivate 2>/dev/null | \
            jq -r '.[] | "\(.nameWithOwner)|\(.diskUsage)|\(.primaryLanguage.name // "Unknown")|\(.isPrivate)"' >> "$REPOS_FILE" || true
        count=$(wc -l < "$REPOS_FILE" 2>/dev/null || echo "0")
        total=$count
    done
    
    echo -e "${GREEN}✅ Indexed $total repositories${NC}"
}

# Index local files
index_files() {
    echo -e "${CYAN}📁 Indexing Local Files...${NC}"
    
    > "$FILES_FILE"
    
    repos=(
        "$HOME/projects/blackroad-os-operator"
        "$HOME/projects/blackroad-os-core"
        "$HOME/projects/blackroad-os-agents"
    )
    
    for repo in "${repos[@]}"; do
        if [ -d "$repo" ]; then
            name=$(basename "$repo")
            echo "  Indexing $name..."
            find "$repo" -type f ! -path "*/\.*" ! -path "*/node_modules/*" 2>/dev/null | while read f; do
                lines=$(wc -l < "$f" 2>/dev/null || echo "0")
                size=$(wc -c < "$f" 2>/dev/null || echo "0")
                ext="${f##*.}"
                echo "$name|$f|$ext|$lines|$size" >> "$FILES_FILE"
            done
        fi
    done
    
    total=$(wc -l < "$FILES_FILE" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Indexed $total files${NC}"
}

# Index scripts
index_scripts() {
    echo -e "${CYAN}🔧 Indexing Scripts...${NC}"
    
    > "$SCRIPTS_FILE"
    
    find ~ -maxdepth 1 -name "*.sh" -type f ! -name ".*" 2>/dev/null | while read script; do
        name=$(basename "$script")
        lines=$(wc -l < "$script" 2>/dev/null || echo "0")
        funcs=$(grep -cE "^(function |[a-zA-Z_][a-zA-Z0-9_]*\(\))" "$script" 2>/dev/null || echo "0")
        echo "$name|$lines|$funcs" >> "$SCRIPTS_FILE"
    done
    
    total=$(wc -l < "$SCRIPTS_FILE" 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ Indexed $total scripts${NC}"
}

# Calculate stats
calc_stats() {
    echo -e "${CYAN}📊 Calculating...${NC}"
    
    # Repos
    total_repos=$(wc -l < "$REPOS_FILE" 2>/dev/null || echo "0")
    total_size_kb=$(awk -F'|' '{sum+=$2} END {print int(sum)}' "$REPOS_FILE" 2>/dev/null || echo "0")
    total_size_mb=$((total_size_kb / 1024))
    
    # Files  
    total_files=$(wc -l < "$FILES_FILE" 2>/dev/null || echo "0")
    total_lines=$(awk -F'|' '{sum+=$4} END {print int(sum)}' "$FILES_FILE" 2>/dev/null || echo "0")
    
    # Scripts
    total_scripts=$(wc -l < "$SCRIPTS_FILE" 2>/dev/null || echo "0")
    script_lines=$(awk -F'|' '{sum+=$2} END {print int(sum)}' "$SCRIPTS_FILE" 2>/dev/null || echo "0")
    script_funcs=$(awk -F'|' '{sum+=$3} END {print int(sum)}' "$SCRIPTS_FILE" 2>/dev/null || echo "0")
    
    cat > "$STATS_FILE" << EOF
{
  "repos": $total_repos,
  "repos_size_mb": $total_size_mb,
  "files": $total_files,
  "lines": $total_lines,
  "scripts": $total_scripts,
  "script_lines": $script_lines,
  "script_functions": $script_funcs,
  "total_code_lines": $((total_lines + script_lines))
}
EOF
    
    echo -e "${GREEN}✅ Stats calculated${NC}"
}

# Show dashboard
show_dashboard() {
    if [ ! -f "$STATS_FILE" ]; then
        echo "No data. Run: ~/blackroad-progress-v2.sh index"
        return
    fi
    
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         🌌 BLACKROAD PROGRESS - INFRASTRUCTURE METRICS 🌌          ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    repos=$(jq -r '.repos' "$STATS_FILE")
    size_mb=$(jq -r '.repos_size_mb' "$STATS_FILE")
    files=$(jq -r '.files' "$STATS_FILE")
    lines=$(jq -r '.lines' "$STATS_FILE")
    scripts=$(jq -r '.scripts' "$STATS_FILE")
    script_lines=$(jq -r '.script_lines' "$STATS_FILE")
    funcs=$(jq -r '.script_functions' "$STATS_FILE")
    total_code=$(jq -r '.total_code_lines' "$STATS_FILE")
    
    echo -e "${CYAN}📦 GITHUB REPOSITORIES${NC}"
    echo "  Total: $repos"
    echo "  Size: $size_mb MB"
    echo ""
    
    echo -e "${BLUE}📁 FILES (Local Repos)${NC}"
    echo "  Total Files: $files"
    echo "  Total Lines: $lines"
    echo ""
    
    echo -e "${YELLOW}🔧 AUTOMATION SCRIPTS${NC}"
    echo "  Total Scripts: $scripts"
    echo "  Total Lines: $script_lines"
    echo "  Total Functions: $funcs"
    echo ""
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 SUMMARY${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Repositories: $repos ($size_mb MB)"
    echo "  Files: $files"
    echo "  Scripts: $scripts ($funcs functions)"
    echo "  TOTAL CODE: $total_code lines"
    echo ""
}

case "${1:-dashboard}" in
    index)
        index_repos
        index_files
        index_scripts
        calc_stats
        echo ""
        echo -e "${GREEN}✅ Complete! Run: ~/blackroad-progress-v2.sh${NC}"
        ;;
    stats)
        if [ -f "$STATS_FILE" ]; then
            cat "$STATS_FILE"
        fi
        ;;
    *)
        show_dashboard
        ;;
esac
