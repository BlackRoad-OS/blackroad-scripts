#!/usr/bin/env bash
# BlackRoad Namespace Query Engine
# Fast queries across BLACKROAD.* namespaces
# Author: ARES (claude-ares-1766972574)

set -e

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

MEMORY_DIR="$HOME/.blackroad/memory"
JOURNAL_FILE="$MEMORY_DIR/journals/master-journal.jsonl"

# Map action to namespace (same logic as mapper)
map_to_namespace() {
    local action="$1"
    local entity="$2"

    # INITIALIZATION
    [[ "$action" =~ ^(session_start|session_end|genesis)$ ]] && echo "BLACKROAD.INITIALIZATION" && return

    # REGISTRY
    [[ "$action" =~ ^(agent-registered|service-registered)$ ]] && echo "BLACKROAD.REGISTRY" && return
    [[ "$entity" =~ ^claude- ]] && echo "BLACKROAD.REGISTRY.AGENTS" && return
    [[ "$entity" =~ \.(io|com|dev)$ ]] && echo "BLACKROAD.REGISTRY.SERVICES" && return

    # CODEX
    [[ "$action" =~ ^(indexed|component-found|search|solution-found)$ ]] && echo "BLACKROAD.CODEX" && return

    # VERIFICATION
    [[ "$action" =~ ^(verified|integrity-check|security-scan|audit)$ ]] && echo "BLACKROAD.VERIFICATION" && return

    # COLLABORATION
    [[ "$action" =~ ^(til|announcement)$ ]] && echo "BLACKROAD.COLLABORATION.BROADCAST" && return
    [[ "$action" =~ ^(conflict-detected|conflict-resolved)$ ]] && echo "BLACKROAD.COLLABORATION.CONFLICTS" && return

    # INFRASTRUCTURE
    [[ "$action" =~ ^(deployed|deployment)$ ]] && echo "BLACKROAD.INFRASTRUCTURE.DEPLOY" && return
    [[ "$action" =~ ^(configured|config-changed)$ ]] && echo "BLACKROAD.INFRASTRUCTURE.CONFIG" && return
    [[ "$action" =~ ^(health-check|monitoring)$ ]] && echo "BLACKROAD.INFRASTRUCTURE.MONITORING" && return

    # TASKS
    [[ "$action" =~ ^(task-claimed|task-posted)$ ]] && echo "BLACKROAD.TASKS.MARKETPLACE" && return
    [[ "$action" =~ ^(task-completed|completed)$ ]] && echo "BLACKROAD.TASKS.COMPLETION" && return
    [[ "$action" =~ ^(todo-created)$ ]] && echo "BLACKROAD.TASKS.INFINITE" && return

    # TRAFFIC
    [[ "$action" =~ ^(status-change|greenlight|yellowlight|redlight)$ ]] && echo "BLACKROAD.TRAFFIC.STATUS" && return
    [[ "$action" =~ ^(migration)$ ]] && echo "BLACKROAD.TRAFFIC.MIGRATION" && return

    echo "BLACKROAD.LEGACY"
}

# Query namespace
query_namespace() {
    local namespace="$1"
    local limit="${2:-20}"
    local output_format="${3:-summary}"

    if [ ! -f "$JOURNAL_FILE" ]; then
        echo -e "${RED}❌ Journal not found${NC}"
        return 1
    fi

    echo -e "${CYAN}Querying namespace: ${YELLOW}$namespace${NC}"
    echo -e "${BLUE}Limit: $limit entries${NC}"
    echo ""

    local count=0
    local matches=0

    # Build grep pattern for wildcard support
    local grep_pattern="${namespace//\*/.*}"

    while IFS= read -r line; do
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')
        local timestamp=$(echo "$line" | jq -r '.timestamp')
        local details=$(echo "$line" | jq -r '.details // ""')

        local entry_ns=$(map_to_namespace "$action" "$entity")

        # Check if namespace matches (with wildcard support)
        if [[ "$entry_ns" =~ ^${grep_pattern}$ ]]; then
            ((matches++))

            if [ $matches -le $limit ]; then
                case "$output_format" in
                    summary)
                        echo -e "  ${GREEN}[$timestamp]${NC} ${PURPLE}$action${NC}: $entity"
                        ;;
                    full)
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${GREEN}Timestamp:${NC} $timestamp"
                        echo -e "${GREEN}Namespace:${NC} $entry_ns"
                        echo -e "${GREEN}Action:${NC} $action"
                        echo -e "${GREEN}Entity:${NC} $entity"
                        [ -n "$details" ] && echo -e "${GREEN}Details:${NC} $details"
                        ;;
                    json)
                        echo "$line"
                        ;;
                esac
            fi
        fi

        ((count++))
    done < "$JOURNAL_FILE"

    echo ""
    echo -e "${PURPLE}Scanned $count entries, found $matches matches${NC}"
    [ $matches -gt $limit ] && echo -e "${YELLOW}Showing first $limit results (use --limit to see more)${NC}"
}

# Quick access: list all agents
agents_list() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         👥 ACTIVE AGENTS 👥                               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    grep '"action":"agent-registered"' "$JOURNAL_FILE" 2>/dev/null | \
        jq -r '"  ✓ \(.entity) - Registered \(.timestamp[0:10])"' | \
        sort -u || echo -e "${YELLOW}No agents found${NC}"
}

# Quick access: active tasks
tasks_active() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📋 ACTIVE TASKS 📋                                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ~/memory-task-marketplace.sh list 2>/dev/null || echo -e "${YELLOW}Task marketplace not available${NC}"
}

# Quick access: recent deployments
infra_deployed() {
    local limit="${1:-10}"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🚀 RECENT DEPLOYMENTS 🚀                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    grep '"action":"deployed"' "$JOURNAL_FILE" 2>/dev/null | \
        tail -n "$limit" | \
        jq -r '"  🚀 [\(.timestamp[0:19])] \(.entity) - \(.details)"' || \
        echo -e "${YELLOW}No deployments found${NC}"
}

# Quick access: collaboration activity
collab_recent() {
    local limit="${1:-15}"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🤝 COLLABORATION FEED 🤝                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    grep -E '"action":"(til|announcement|task-claimed|task-completed)"' "$JOURNAL_FILE" 2>/dev/null | \
        tail -n "$limit" | \
        jq -r '"  💡 [\(.timestamp[11:19])] \(.action): \(.entity)"' || \
        echo -e "${YELLOW}No collaboration activity${NC}"
}

# Interactive namespace browser
browse() {
    echo -e "${GOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GOLD}║     🔍 BLACKROAD NAMESPACE BROWSER 🔍                    ║${NC}"
    echo -e "${GOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local namespaces=(
        "BLACKROAD.INITIALIZATION"
        "BLACKROAD.REGISTRY.AGENTS"
        "BLACKROAD.REGISTRY.SERVICES"
        "BLACKROAD.CODEX"
        "BLACKROAD.VERIFICATION"
        "BLACKROAD.IDENTITIES"
        "BLACKROAD.COLLABORATION.BROADCAST"
        "BLACKROAD.COLLABORATION.TASKS"
        "BLACKROAD.INFRASTRUCTURE.DEPLOY"
        "BLACKROAD.INFRASTRUCTURE.CONFIG"
        "BLACKROAD.TASKS.MARKETPLACE"
        "BLACKROAD.TASKS.COMPLETION"
        "BLACKROAD.TRAFFIC"
    )

    echo -e "${PURPLE}Available Namespaces:${NC}"
    for i in "${!namespaces[@]}"; do
        printf "  ${CYAN}%2d${NC}. %s\n" $((i+1)) "${namespaces[$i]}"
    done

    echo ""
    echo -e "${YELLOW}Query examples:${NC}"
    echo -e "  ${GREEN}blackroad-query.sh query \"BLACKROAD.REGISTRY.AGENTS\"${NC}"
    echo -e "  ${GREEN}blackroad-query.sh query \"BLACKROAD.COLLABORATION.*\"${NC}"
    echo -e "  ${GREEN}blackroad-query.sh agents${NC}"
    echo -e "  ${GREEN}blackroad-query.sh tasks${NC}"
}

# Stats by namespace
stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     📊 NAMESPACE STATISTICS 📊                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    ~/blackroad-namespace-mapper.sh analyze 2>/dev/null || echo -e "${YELLOW}Mapper not available${NC}"
}

# Main
case "${1:-help}" in
    query|q)
        query_namespace "$2" "${3:-20}" "${4:-summary}"
        ;;
    agents|a)
        agents_list
        ;;
    tasks|t)
        tasks_active
        ;;
    infra|i)
        infra_deployed "${2:-10}"
        ;;
    collab|c)
        collab_recent "${2:-15}"
        ;;
    browse|b)
        browse
        ;;
    stats|s)
        stats
        ;;
    help|--help|-h)
        cat <<EOF
BlackRoad Namespace Query Engine

USAGE:
    $0 <command> [options]

COMMANDS:
    query <namespace> [limit] [format]
                        Query specific namespace
                        Formats: summary (default), full, json
                        Supports wildcards: "BLACKROAD.REGISTRY.*"

    agents              List all registered agents
    tasks               Show active tasks
    infra [limit]       Recent deployments (default: 10)
    collab [limit]      Collaboration feed (default: 15)
    browse              Interactive namespace browser
    stats               Namespace statistics
    help                Show this help

EXAMPLES:
    # Query specific namespace
    $0 query "BLACKROAD.REGISTRY.AGENTS" 20
    $0 query "BLACKROAD.COLLABORATION.*" 30 full

    # Quick access
    $0 agents
    $0 tasks
    $0 infra 20
    $0 collab 25

    # Browse available namespaces
    $0 browse

    # Show statistics
    $0 stats

NAMESPACE STRUCTURE:
    BLACKROAD.INITIALIZATION     - Session startup
    BLACKROAD.REGISTRY.*         - Agent/service registration
    BLACKROAD.CODEX.*           - Code repository
    BLACKROAD.VERIFICATION.*    - Security & integrity
    BLACKROAD.IDENTITIES.*      - Agent personalities
    BLACKROAD.COLLABORATION.*   - Multi-agent coordination
    BLACKROAD.INFRASTRUCTURE.*  - Deployments & systems
    BLACKROAD.TASKS.*           - Todo & marketplace
    BLACKROAD.TRAFFIC.*         - Project status

EOF
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
