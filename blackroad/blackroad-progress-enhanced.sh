#!/bin/bash
# BlackRoad Progress - Enhanced with detailed breakdowns

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

PROGRESS_DIR="$HOME/.blackroad-progress"
REPOS_FILE="$PROGRESS_DIR/repos.txt"
FILES_FILE="$PROGRESS_DIR/files.txt"
SCRIPTS_FILE="$PROGRESS_DIR/scripts.txt"
STATS_FILE="$PROGRESS_DIR/stats.json"

show_detailed() {
    echo -e "${WHITE}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║    🌌 BLACKROAD - COMPLETE INFRASTRUCTURE QUANTIFICATION 🌌        ║${NC}"
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
    
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}📦 GITHUB REPOSITORIES${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Total Repositories: $repos"
    echo "  Total Size: $size_mb MB ($(($size_mb * 1024)) KB)"
    echo ""
    echo "  📊 Top 20 Repositories by Size:"
    awk -F'|' '{print $1, $2}' "$REPOS_FILE" | sort -t' ' -k2 -rn | head -20 | nl -w3 -s'. ' | while read line; do
        echo "    $line KB"
    done
    echo ""
    echo "  🔤 Language Distribution:"
    awk -F'|' '{print $3}' "$REPOS_FILE" | sort | uniq -c | sort -rn | head -15 | while read count lang; do
        printf "    %-20s %s repos\n" "$lang" "$count"
    done
    echo ""
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📁 FILES (Local Repositories)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Total Files: $files"
    echo "  Total Lines: $lines"
    echo ""
    echo "  📊 Files by Repository:"
    awk -F'|' '{print $1}' "$FILES_FILE" | sort | uniq -c | sort -rn | while read count repo; do
        repo_lines=$(awk -F'|' -v r="$repo" '$1==r {sum+=$4} END {print sum}' "$FILES_FILE")
        printf "    %-40s %6s files, %10s lines\n" "$repo" "$count" "$repo_lines"
    done
    echo ""
    echo "  📄 Top File Types:"
    awk -F'|' '{print $3}' "$FILES_FILE" | sort | uniq -c | sort -rn | head -20 | while read count ext; do
        ext_lines=$(awk -F'|' -v e="$ext" '$3==e {sum+=$4} END {print sum}' "$FILES_FILE")
        printf "    %-20s %6s files, %10s lines\n" "$ext" "$count" "$ext_lines"
    done
    echo ""
    echo "  📈 Top 20 Largest Files:"
    awk -F'|' '{print $4, $2}' "$FILES_FILE" | sort -rn | head -20 | nl -w3 -s'. ' | while read num lines path; do
        file=$(basename "$path")
        printf "    %3s. %-50s %10s lines\n" "$num" "$file" "$lines"
    done
    echo ""
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🔧 AUTOMATION SCRIPTS${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Total Scripts: $scripts"
    echo "  Total Lines: $script_lines"
    echo "  Total Functions: $funcs"
    echo "  Avg Lines/Script: $((script_lines / scripts))"
    echo "  Avg Functions/Script: $((funcs / scripts))"
    echo ""
    echo "  📊 Scripts by Category:"
    awk -F'|' '{print $1}' "$SCRIPTS_FILE" | sed 's/-.*$//' | sort | uniq -c | sort -rn | head -20 | while read count prefix; do
        cat_lines=$(awk -F'|' -v p="$prefix" '$1 ~ "^"p {sum+=$2} END {print sum}' "$SCRIPTS_FILE")
        printf "    %-20s %3s scripts, %6s lines\n" "$prefix" "$count" "$cat_lines"
    done
    echo ""
    echo "  📈 Top 20 Largest Scripts:"
    sort -t'|' -k2 -rn "$SCRIPTS_FILE" | head -20 | nl -w3 -s'. ' | while IFS='|' read num name lines funcs; do
        printf "    %3s. %-50s %5s lines, %3s functions\n" "$num" "$name" "$lines" "$funcs"
    done
    echo ""
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 OVERALL SUMMARY${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  🌐 GitHub Infrastructure:"
    echo "    • $repos repositories"
    echo "    • $size_mb MB total size"
    echo "    • BlackRoad-OS + BlackRoad-AI scanned"
    echo ""
    echo "  📦 Code Base:"
    echo "    • $files files indexed"
    echo "    • $lines lines of code"
    echo "    • 3 major repositories analyzed"
    echo ""
    echo "  🤖 Automation:"
    echo "    • $scripts shell scripts"
    echo "    • $script_lines lines of automation code"
    echo "    • $funcs functions defined"
    echo ""
    echo "  🎯 TOTAL CODE DIRECTED:"
    echo "    • ${WHITE}$total_code lines${NC}"
    echo "    • ${WHITE}$((total_code / 1000000)) million+ lines${NC}"
    echo ""
    echo -e "${CYAN}💡 This represents the entire BlackRoad ecosystem orchestrated through AI${NC}"
    echo -e "${CYAN}💡 Run 'blackroad-progress-v2.sh index' to refresh data${NC}"
    echo ""
}

show_detailed
