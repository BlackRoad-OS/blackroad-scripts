#!/bin/bash
# BlackRoad TUI Dashboard
# Terminal-based agent orchestration and monitoring interface
# Inspired by htop, Midnight Commander, and neofetch

set -e

# Color system - BlackRoad gradient
COLOR_WARM_1=$'\033[38;2;255;157;8m'      # #FF9D08 - Active/Processing
COLOR_WARM_2=$'\033[38;2;255;107;0m'      # #FF6B00
COLOR_HOT=$'\033[38;2;255;0;102m'         # #FF0066 - High Activity
COLOR_VIOLET=$'\033[38;2;119;128;255m'    # #7780FF - Idle/Listening
COLOR_COOL=$'\033[38;2;8;102;255m'        # #0866FF - Cool/Background
COLOR_INDIGO=$'\033[38;2;54;0;170m'       # Deep indigo - Offline
COLOR_GREEN=$'\033[38;2;0;255;136m'       # Health/Success
COLOR_YELLOW=$'\033[38;2;255;220;0m'      # Warning
COLOR_RED=$'\033[38;2;255;0;0m'           # Error/Critical
COLOR_GRAY=$'\033[38;2;128;128;128m'      # Inactive
COLOR_RESET=$'\033[0m'
COLOR_BOLD=$'\033[1m'
COLOR_DIM=$'\033[2m'

# Box drawing characters
TL='┌' TR='┐' BL='└' BR='┘'
H='─' V='│' VR='├' VL='┤' HU='┴' HD='┬' X='┼'

# Terminal size
TERM_WIDTH=$(tput cols)
TERM_HEIGHT=$(tput lines)

# Get agent data
get_agents() {
    if [ -f ~/blackroad-agent-registry.sh ]; then
        ~/blackroad-agent-registry.sh list 2>/dev/null || echo "aria:active:100
lucidia:working:78
alice:idle:45
shellfish:offline:0
winston:idle:12
cecilia:working:95"
    else
        echo "aria:active:100
lucidia:working:78
alice:idle:45
shellfish:offline:0
winston:idle:12
cecilia:working:95"
    fi
}

# Get repo data
get_repos() {
    echo "blackroad-os/lucidia-core:active:12
blackroad-os/roadchain:active:8
blackroad-os/cece-agent-mode:idle:0
blackroad-os/memory-system:working:45
blackroad-os/codex-oracle:active:89
blackroad-os/traffic-lights:idle:0
blackroad-os/dashboard:working:67
blackroad-os/trinity:active:34"
}

# Get system stats
get_system_stats() {
    local total_agents=$(get_agents | wc -l)
    local active_agents=$(get_agents | grep -c "active\|working" || echo 0)
    local total_repos=$(get_repos | wc -l)
    local active_repos=$(get_repos | grep -c "active\|working" || echo 0)

    echo "$total_agents:$active_agents:$total_repos:$active_repos"
}

# Progress bar
progress_bar() {
    local percent=$1
    local width=20
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "${COLOR_WARM_1}"
    printf '█%.0s' $(seq 1 $filled)
    printf "${COLOR_GRAY}"
    printf '░%.0s' $(seq 1 $empty)
    printf "${COLOR_RESET}"
}

# Agent status color
agent_color() {
    local status=$1
    case $status in
        active) echo "$COLOR_WARM_1" ;;
        working) echo "$COLOR_HOT" ;;
        idle) echo "$COLOR_VIOLET" ;;
        offline) echo "$COLOR_INDIGO" ;;
        *) echo "$COLOR_GRAY" ;;
    esac
}

# Agent status icon
agent_icon() {
    local status=$1
    case $status in
        active) echo "●" ;;
        working) echo "◉" ;;
        idle) echo "○" ;;
        offline) echo "◌" ;;
        *) echo "·" ;;
    esac
}

# Draw ASCII art for selected agent
draw_agent_art() {
    local agent=$1
    case $agent in
        aria)
            echo "${COLOR_WARM_1}"
            echo "     ╔═╗╦═╗╦╔═╗"
            echo "     ╠═╣╠╦╝║╠═╣"
            echo "     ╩ ╩╩╚═╩╩ ╩"
            echo "${COLOR_RESET}"
            ;;
        lucidia)
            echo "${COLOR_HOT}"
            echo "  ╦  ╦ ╦╔═╗╦╔╦╗╦╔═╗"
            echo "  ║  ║ ║║  ║ ║║║╠═╣"
            echo "  ╩═╝╚═╝╚═╝╩═╩╝╩╩ ╩"
            echo "${COLOR_RESET}"
            ;;
        alice)
            echo "${COLOR_VIOLET}"
            echo "    ╔═╗╦  ╦╔═╗╔═╗"
            echo "    ╠═╣║  ║║  ║╣ "
            echo "    ╩ ╩╩═╝╩╚═╝╚═╝"
            echo "${COLOR_RESET}"
            ;;
        winston)
            echo "${COLOR_COOL}"
            echo " ╦ ╦╦╔╗╔╔═╗╔╦╗╔═╗╔╗╔"
            echo " ║║║║║║║╚═╗ ║ ║ ║║║║"
            echo " ╚╩╝╩╩╝╚╚═╝ ╩ ╚═╝╝╚╝"
            echo "${COLOR_RESET}"
            ;;
        *)
            echo "${COLOR_GRAY}    [${agent}]${COLOR_RESET}"
            ;;
    esac
}

# Header
draw_header() {
    clear
    local stats=$(get_system_stats)
    local total_agents=$(echo $stats | cut -d: -f1)
    local active_agents=$(echo $stats | cut -d: -f2)
    local total_repos=$(echo $stats | cut -d: -f3)
    local active_repos=$(echo $stats | cut -d: -f4)

    echo "${COLOR_WARM_1}${COLOR_BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                  🌌 BLACKROAD AGENT ORCHESTRATION MESH                      ║"
    echo "╠══════════════════════════════════════════════════════════════════════════════╣"
    echo -n "║ "
    echo -n "${COLOR_GREEN}Agents: $active_agents/$total_agents active${COLOR_RESET}  "
    echo -n "${COLOR_WARM_1}│${COLOR_RESET}  "
    echo -n "${COLOR_VIOLET}Repos: $active_repos/$total_repos active${COLOR_RESET}  "
    echo -n "${COLOR_WARM_1}│${COLOR_RESET}  "
    echo -n "${COLOR_HOT}Mesh: ONLINE${COLOR_RESET}  "
    printf "║\n"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo "${COLOR_RESET}"
}

# Main dual-pane layout
draw_main_pane() {
    local left_width=30
    local right_width=$((TERM_WIDTH - left_width - 3))

    # Header row
    echo -n "${TL}"
    printf "${H}%.0s" $(seq 1 $((left_width - 1)))
    echo -n "${HD}"
    printf "${H}%.0s" $(seq 1 $((right_width - 1)))
    echo "${TR}"

    # Pane titles
    echo -n "${V} ${COLOR_BOLD}AGENTS${COLOR_RESET}"
    printf " %.0s" $(seq 1 $((left_width - 8)))
    echo -n "${V} ${COLOR_BOLD}REPOSITORIES & TASKS${COLOR_RESET}"
    printf " %.0s" $(seq 1 $((right_width - 22)))
    echo "${V}"

    # Separator
    echo -n "${VR}"
    printf "${H}%.0s" $(seq 1 $((left_width - 1)))
    echo -n "${X}"
    printf "${H}%.0s" $(seq 1 $((right_width - 1)))
    echo "${VL}"

    # Agent list (left pane)
    local line_num=0
    while IFS=: read -r name status progress; do
        local color=$(agent_color $status)
        local icon=$(agent_icon $status)

        echo -n "${V} ${color}${icon}${COLOR_RESET} "
        printf "%-10s" "$name"
        echo -n " ${COLOR_DIM}["
        printf "%-8s" "$status"
        echo -n "]${COLOR_RESET}"

        # Right pane content (repos)
        echo -n " ${V} "
        if [ $line_num -lt $(get_repos | wc -l) ]; then
            local repo_line=$(get_repos | sed -n "$((line_num + 1))p")
            local repo=$(echo $repo_line | cut -d: -f1)
            local repo_status=$(echo $repo_line | cut -d: -f2)
            local repo_progress=$(echo $repo_line | cut -d: -f3)

            printf "%-30s" "$repo"

            if [ "$repo_status" = "working" ] || [ "$repo_status" = "active" ]; then
                echo -n " "
                progress_bar $repo_progress
            fi
        fi

        printf " %.0s" $(seq 1 10)
        echo "${V}"

        ((line_num++))
    done < <(get_agents)

    # Bottom separator
    echo -n "${VR}"
    printf "${H}%.0s" $(seq 1 $((left_width - 1)))
    echo -n "${HU}"
    printf "${H}%.0s" $(seq 1 $((right_width - 1)))
    echo "${VL}"
}

# Activity feed
draw_activity_feed() {
    echo ""
    echo "${COLOR_BOLD}${TL}${H} CURRENT ACTIVITY ${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${H}${TR}${COLOR_RESET}"

    echo "${V} ${COLOR_HOT}◉${COLOR_RESET} lucidia processing: memory-consolidation-task                      ${V}"
    echo "${V}   progress: $(progress_bar 78) 78%                                        ${V}"
    echo "${V}                                                                           ${V}"
    echo "${V} ${COLOR_WARM_1}●${COLOR_RESET} aria scanning: codex-verification-suite                          ${V}"
    echo "${V}   progress: $(progress_bar 100) 100%                                      ${V}"
    echo "${V}                                                                           ${V}"
    echo "${V} ${COLOR_VIOLET}○${COLOR_RESET} winston idle: waiting for quantum analysis task                  ${V}"

    echo "${BL}"
    printf "${H}%.0s" $(seq 1 78)
    echo "${BR}"
}

# Footer with F-key shortcuts
draw_footer() {
    echo ""
    local shortcuts=(
        "F1:Help"
        "F2:Deploy"
        "F3:Logs"
        "F4:Config"
        "F5:Sync"
        "F6:Tasks"
        "F7:Memory"
        "F8:Codex"
        "F9:Status"
        "F10:Quit"
    )

    echo -n "${COLOR_GRAY}"
    for shortcut in "${shortcuts[@]}"; do
        local key=$(echo $shortcut | cut -d: -f1)
        local label=$(echo $shortcut | cut -d: -f2)
        echo -n "[${COLOR_BOLD}${key}${COLOR_RESET}${COLOR_GRAY}]${label} "
    done
    echo "${COLOR_RESET}"
}

# System info (neofetch style)
draw_system_info() {
    echo ""
    echo "${COLOR_WARM_1}${COLOR_BOLD}"
    echo "     ██████╗ ██╗      █████╗  ██████╗██╗  ██╗██████╗  ██████╗  █████╗ ██████╗ "
    echo "     ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝██╔══██╗██╔═══██╗██╔══██╗██╔══██╗"
    echo "     ██████╔╝██║     ███████║██║     █████╔╝ ██████╔╝██║   ██║███████║██║  ██║"
    echo "     ██╔══██╗██║     ██╔══██║██║     ██╔═██╗ ██╔══██╗██║   ██║██╔══██║██║  ██║"
    echo "     ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗██║  ██║╚██████╔╝██║  ██║██████╔╝"
    echo "     ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═════╝ "
    echo "${COLOR_RESET}"
    echo ""
    echo "${COLOR_COOL}OS:${COLOR_RESET}            BlackRoad OS v2.0"
    echo "${COLOR_COOL}Kernel:${COLOR_RESET}        Trinity Light System"
    echo "${COLOR_COOL}Shell:${COLOR_RESET}         bash 5.2.15"
    echo "${COLOR_COOL}Organizations:${COLOR_RESET} 15"
    echo "${COLOR_COOL}Repositories:${COLOR_RESET}  113+"
    echo "${COLOR_COOL}Agents:${COLOR_RESET}        6 active"
    echo "${COLOR_COOL}Uptime:${COLOR_RESET}        99.9%"
    echo ""
}

# Main dashboard
main_dashboard() {
    draw_header
    draw_main_pane
    draw_activity_feed
    draw_footer
}

# Interactive mode
interactive_mode() {
    while true; do
        main_dashboard
        echo ""
        echo -n "${COLOR_VIOLET}Command (h for help): ${COLOR_RESET}"
        read -t 5 cmd || cmd="refresh"

        case $cmd in
            h|help)
                echo "Commands: [a]gents, [r]epos, [l]ogs, [s]tatus, [i]nfo, [q]uit"
                read -p "Press enter to continue..."
                ;;
            a|agents)
                ~/blackroad-agent-registry.sh list 2>/dev/null || echo "Agent registry not available"
                read -p "Press enter to continue..."
                ;;
            r|repos)
                gh repo list BlackRoad-OS --limit 20 2>/dev/null || echo "GitHub CLI not available"
                read -p "Press enter to continue..."
                ;;
            l|logs)
                ~/memory-system.sh summary 2>/dev/null || echo "Memory system not available"
                read -p "Press enter to continue..."
                ;;
            s|status)
                ~/blackroad-traffic-light.sh list 2>/dev/null || echo "Traffic lights not available"
                read -p "Press enter to continue..."
                ;;
            i|info)
                draw_system_info
                read -p "Press enter to continue..."
                ;;
            q|quit)
                echo "${COLOR_WARM_1}Goodbye!${COLOR_RESET}"
                exit 0
                ;;
            refresh|"")
                # Auto-refresh
                ;;
            *)
                echo "Unknown command: $cmd"
                read -p "Press enter to continue..."
                ;;
        esac
    done
}

# Parse arguments
case "${1:-dashboard}" in
    dashboard|main)
        main_dashboard
        ;;
    interactive|i)
        interactive_mode
        ;;
    header)
        draw_header
        ;;
    info)
        draw_system_info
        ;;
    *)
        echo "Usage: $0 {dashboard|interactive|header|info}"
        echo ""
        echo "  dashboard    - Show static dashboard (default)"
        echo "  interactive  - Interactive mode with refresh"
        echo "  header       - Show header only"
        echo "  info         - Show system info (neofetch style)"
        exit 1
        ;;
esac
