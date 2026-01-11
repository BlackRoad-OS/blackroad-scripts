#!/bin/bash
#
# BlackRoad Progress - Per-Repo Detailed Analysis
# Analyzes every repository with file breakdowns, language stats, and more
#

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

PROGRESS_DIR="$HOME/.blackroad-progress"
FILES_FILE="$PROGRESS_DIR/files.txt"

# Analyze a specific repo
analyze_repo() {
    local repo_name="$1"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 REPOSITORY: $repo_name${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Overall stats
    total_files=$(awk -F'|' -v r="$repo_name" '$1==r' "$FILES_FILE" | wc -l)
    total_lines=$(awk -F'|' -v r="$repo_name" '$1==r {sum+=$4} END {print sum}' "$FILES_FILE")
    total_bytes=$(awk -F'|' -v r="$repo_name" '$1==r {sum+=$5} END {print sum}' "$FILES_FILE")
    total_mb=$((total_bytes / 1024 / 1024))

    echo ""
    echo "  📊 Overview:"
    echo "    Files: $total_files"
    echo "    Lines: $total_lines"
    echo "    Size: $total_mb MB"
    echo ""

    # File types
    echo "  📄 File Types:"
    awk -F'|' -v r="$repo_name" '$1==r {print $3}' "$FILES_FILE" | sort | uniq -c | sort -rn | head -15 | while read count ext; do
        ext_lines=$(awk -F'|' -v r="$repo_name" -v e="$ext" '$1==r && $3==e {sum+=$4} END {print sum}' "$FILES_FILE")
        printf "    %-15s %6s files, %10s lines\n" "$ext" "$count" "$ext_lines"
    done
    echo ""

    # Top 10 largest files
    echo "  📈 Top 10 Largest Files:"
    awk -F'|' -v r="$repo_name" '$1==r {print $4, $2}' "$FILES_FILE" | sort -rn | head -10 | nl -w3 -s'. ' | while read num lines path; do
        file=$(basename "$path")
        printf "    %3s. %-50s %10s lines\n" "$num" "$file" "$lines"
    done
    echo ""

    # Directory structure depth
    echo "  🗂️  Directory Depth:"
    awk -F'|' -v r="$repo_name" '$1==r {
        n = split($2, parts, "/")
        depth[n]++
    } END {
        for (d in depth) print d, depth[d]
    }' "$FILES_FILE" | sort -n | while read depth count; do
        printf "    %2s levels deep: %s files\n" "$depth" "$count"
    done
    echo ""
}

# Show all repos
show_all_repos() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║         🌌 BLACKROAD - PER-REPOSITORY DETAILED ANALYSIS 🌌         ║${NC}"
    echo -e "${WHITE}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    repos=$(awk -F'|' '{print $1}' "$FILES_FILE" | sort -u)

    for repo in $repos; do
        analyze_repo "$repo"
    done

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Analysis Complete${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

case "${1:-all}" in
    all)
        show_all_repos
        ;;
    *)
        analyze_repo "$1"
        ;;
esac
