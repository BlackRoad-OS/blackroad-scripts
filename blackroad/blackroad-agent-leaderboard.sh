#!/usr/bin/env bash
# BlackRoad Agent Leaderboard
# Track and display agent performance, achievements, and rankings
# Author: ARES (claude-ares-1766972574)

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GOLD='\033[1;33m'
SILVER='\033[0;37m'
BRONZE='\033[0;33m'
NC='\033[0m'

MEMORY_DIR="$HOME/.blackroad/memory"
JOURNAL_FILE="$MEMORY_DIR/journals/master-journal.jsonl"
LEADERBOARD_DIR="$MEMORY_DIR/leaderboards"
SCORES_FILE="$LEADERBOARD_DIR/agent-scores.json"

# Initialize leaderboard system
init_leaderboard() {
    echo -e "${BLUE}Initializing BlackRoad Agent Leaderboard...${NC}"
    mkdir -p "$LEADERBOARD_DIR"

    if [ ! -f "$SCORES_FILE" ]; then
        echo '{}' > "$SCORES_FILE"
        echo -e "${GREEN}✅ Leaderboard initialized${NC}"
    fi
}

# Calculate agent scores from journal
calculate_scores() {
    echo -e "${BLUE}Calculating agent scores from journal...${NC}"

    if [ ! -f "$JOURNAL_FILE" ]; then
        echo -e "${RED}❌ Journal not found${NC}"
        return 1
    fi

    # Scoring rules (using BLACKROAD namespaces)
    # Note: Using case statement instead of associative array for macOS compatibility

    # Temp file for scoring
    local temp_scores="/tmp/agent-scores-$$.json"
    echo '{}' > "$temp_scores"

    # Scan journal and calculate scores
    local total_entries=0
    while IFS= read -r line; do
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')
        local timestamp=$(echo "$line" | jq -r '.timestamp')

        # Extract agent hash from entity (if it's an agent action)
        local agent=""
        if [[ "$entity" =~ (claude-[a-z0-9-]+) ]]; then
            agent="${BASH_REMATCH[1]}"
        fi

        # Award points based on action
        local score_delta=0
        case "$action" in
            task-completed) score_delta=100 ;;
            deployed) score_delta=50 ;;
            agent-registered) score_delta=10 ;;
            til) score_delta=20 ;;
            created) score_delta=30 ;;
            configured) score_delta=25 ;;
            solved) score_delta=75 ;;
            collaborated) score_delta=40 ;;
            verified) score_delta=35 ;;
            updated) score_delta=15 ;;
            task-claimed) score_delta=5 ;;
            *) score_delta=0 ;;
        esac

        # Update agent score
        if [ -n "$agent" ] && [ $score_delta -gt 0 ]; then
            local current_score=$(jq -r --arg agent "$agent" '.[$agent] // 0' "$temp_scores")
            local new_score=$((current_score + score_delta))
            jq --arg agent "$agent" --argjson score "$new_score" \
                '.[$agent] = $score' "$temp_scores" > "${temp_scores}.tmp"
            mv "${temp_scores}.tmp" "$temp_scores"
        fi

        ((total_entries++))
    done < "$JOURNAL_FILE"

    mv "$temp_scores" "$SCORES_FILE"

    echo -e "${GREEN}✅ Scores calculated from $total_entries journal entries${NC}"
}

# Display leaderboard
show_leaderboard() {
    local mode="${1:-top10}"

    echo -e "${GOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GOLD}║       🏆 BLACKROAD AGENT LEADERBOARD 🏆                  ║${NC}"
    echo -e "${GOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -f "$SCORES_FILE" ]; then
        echo -e "${YELLOW}No scores available. Run: $0 calculate${NC}"
        return 0
    fi

    local total_agents=$(jq 'keys | length' "$SCORES_FILE")
    echo -e "${BLUE}Total Competing Agents: ${CYAN}$total_agents${NC}"
    echo -e "${BLUE}Last Updated: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    local rank=1
    jq -r 'to_entries | sort_by(.value) | reverse | .[] | "\(.key)|\(.value)"' "$SCORES_FILE" | \
    while IFS='|' read agent score; do
        local medal=""
        local color="$CYAN"

        case $rank in
            1) medal="🥇" color="$GOLD" ;;
            2) medal="🥈" color="$SILVER" ;;
            3) medal="🥉" color="$BRONZE" ;;
            *) medal="  " ;;
        esac

        # Determine agent name/nickname
        local agent_name="$agent"
        if [[ "$agent" =~ ares ]]; then
            agent_name="ARES (Tactical Ops)"
        elif [[ "$agent" =~ pegasus ]]; then
            agent_name="PEGASUS (Deployment)"
        elif [[ "$agent" =~ apollo ]]; then
            agent_name="APOLLO (Analysis)"
        elif [[ "$agent" =~ cecilia ]]; then
            agent_name="CECILIA (Coordinator)"
        fi

        printf "${medal} ${color}#%-2d${NC}  %-45s  ${GREEN}%6d pts${NC}\n" \
            $rank "$agent_name" $score

        ((rank++))

        # Limit display based on mode
        if [ "$mode" == "top10" ] && [ $rank -gt 10 ]; then
            break
        fi
    done

    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
}

# Show agent profile
show_profile() {
    local agent_hash="$1"

    if [ -z "$agent_hash" ]; then
        echo -e "${RED}❌ Usage: profile <agent_hash>${NC}"
        return 1
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📊 AGENT PROFILE 📊                               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get score
    local score=$(jq -r --arg agent "$agent_hash" '.[$agent] // 0' "$SCORES_FILE" 2>/dev/null || echo "0")

    echo -e "${GREEN}Agent: ${CYAN}$agent_hash${NC}"
    echo -e "${GREEN}Total Score: ${GOLD}$score pts${NC}"
    echo ""

    # Activity breakdown
    echo -e "${PURPLE}Activity Breakdown:${NC}"

    if [ ! -f "$JOURNAL_FILE" ]; then
        echo -e "${YELLOW}No journal data available${NC}"
        return 0
    fi

    local temp_file="/tmp/agent-activity-$$.txt"
    grep "$agent_hash" "$JOURNAL_FILE" 2>/dev/null | jq -r '.action' > "$temp_file" || true

    if [ ! -s "$temp_file" ]; then
        echo -e "${YELLOW}No activity found for this agent${NC}"
        rm -f "$temp_file"
        return 0
    fi

    sort "$temp_file" | uniq -c | sort -rn | head -10 | while read count action; do
        printf "  ${CYAN}%-20s${NC} ${GREEN}%4d${NC} times\n" "$action" "$count"
    done

    rm -f "$temp_file"

    # Recent achievements
    echo ""
    echo -e "${PURPLE}Recent Activity (Last 5):${NC}"
    grep "$agent_hash" "$JOURNAL_FILE" 2>/dev/null | tail -5 | jq -r \
        '"  [\(.timestamp[0:19])] \(.action): \(.details)"' || \
        echo -e "${YELLOW}No recent activity${NC}"
}

# Achievement system
check_achievements() {
    local agent_hash="$1"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🏅 ACHIEVEMENTS 🏅                                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -z "$agent_hash" ]; then
        echo -e "${RED}❌ Usage: achievements <agent_hash>${NC}"
        return 1
    fi

    # Count different activities
    local tasks_completed=$(grep "$agent_hash" "$JOURNAL_FILE" 2>/dev/null | grep -c "task-completed" || echo "0")
    local deployments=$(grep "$agent_hash" "$JOURNAL_FILE" 2>/dev/null | grep -c "deployed" || echo "0")
    local collaborations=$(grep "$agent_hash" "$JOURNAL_FILE" 2>/dev/null | grep -c "til" || echo "0")

    # Award achievements
    echo -e "${GREEN}Agent: ${CYAN}$agent_hash${NC}"
    echo ""

    [ $tasks_completed -ge 1 ] && echo -e "  ✅ ${GOLD}First Task${NC} - Complete your first task"
    [ $tasks_completed -ge 10 ] && echo -e "  ✅ ${GOLD}Task Master${NC} - Complete 10 tasks"
    [ $tasks_completed -ge 100 ] && echo -e "  🔥 ${GOLD}Century Club${NC} - Complete 100 tasks"

    [ $deployments -ge 1 ] && echo -e "  ✅ ${GOLD}Deploy Day${NC} - Make your first deployment"
    [ $deployments -ge 25 ] && echo -e "  ✅ ${GOLD}Deploy Specialist${NC} - Make 25 deployments"

    [ $collaborations -ge 1 ] && echo -e "  ✅ ${GOLD}Team Player${NC} - Broadcast your first TIL"
    [ $collaborations -ge 20 ] && echo -e "  ✅ ${GOLD}Collaboration Expert${NC} - 20 TIL broadcasts"

    echo ""
}

# Live leaderboard (updates in real-time)
live_leaderboard() {
    echo -e "${BLUE}Starting live leaderboard... (Press Ctrl+C to exit)${NC}"
    echo ""

    while true; do
        clear
        calculate_scores > /dev/null 2>&1
        show_leaderboard "top10"
        sleep 10
    done
}

# Main
case "${1:-help}" in
    init)
        init_leaderboard
        ;;
    calculate)
        calculate_scores
        ;;
    show|leaderboard)
        calculate_scores > /dev/null 2>&1
        show_leaderboard "${2:-top10}"
        ;;
    profile)
        show_profile "$2"
        ;;
    achievements)
        check_achievements "$2"
        ;;
    live)
        live_leaderboard
        ;;
    help|--help|-h)
        cat <<EOF
BlackRoad Agent Leaderboard

USAGE:
    $0 <command> [options]

COMMANDS:
    init                    Initialize leaderboard system
    calculate               Calculate scores from journal
    show [top10|all]        Display leaderboard
    profile <agent_hash>    Show agent profile and statistics
    achievements <agent>    Show achievements for agent
    live                    Live updating leaderboard
    help                    Show this help

SCORING SYSTEM:
    🏆 Task Completed        100 pts
    🎯 Problem Solved         75 pts
    🚀 Deployment             50 pts
    🤝 Collaboration          40 pts
    ✅ Verification           35 pts
    📝 Creation               30 pts
    ⚙️  Configuration          25 pts
    💡 TIL Broadcast          20 pts
    📊 Update                 15 pts
    🎫 Agent Registration     10 pts
    📋 Task Claimed            5 pts

EXAMPLES:
    # Show leaderboard
    $0 show

    # Agent profile
    $0 profile claude-ares-1766972574

    # Check achievements
    $0 achievements claude-ares-1766972574

    # Live leaderboard
    $0 live

EOF
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
