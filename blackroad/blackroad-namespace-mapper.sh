#!/usr/bin/env bash
# BlackRoad Namespace Mapper
# Maps existing memory entries to new BLACKROAD.* namespace hierarchy
# Author: ARES (claude-ares-1766972574)

set -e

# Detect bash version and use appropriate approach
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    USE_SIMPLE_COUNT=true
else
    USE_SIMPLE_COUNT=false
fi

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

MEMORY_DIR="$HOME/.blackroad/memory"
JOURNAL_FILE="$MEMORY_DIR/journals/master-journal.jsonl"

# Namespace mapping rules
map_to_namespace() {
    local action="$1"
    local entity="$2"
    local details="$3"

    # INITIALIZATION namespace
    if [[ "$action" == "session_start" ]] || [[ "$action" == "session_end" ]]; then
        echo "BLACKROAD.INITIALIZATION.SESSION"
        return
    fi

    if [[ "$action" == "genesis" ]]; then
        echo "BLACKROAD.INITIALIZATION.GENESIS"
        return
    fi

    # REGISTRY namespace
    if [[ "$action" == "agent-registered" ]] || [[ "$entity" =~ ^claude- ]]; then
        echo "BLACKROAD.REGISTRY.AGENTS"
        return
    fi

    if [[ "$action" == "service-registered" ]] || [[ "$entity" =~ \.(io|com|dev|local)$ ]]; then
        echo "BLACKROAD.REGISTRY.SERVICES"
        return
    fi

    if [[ "$entity" =~ ^(pi|raspberry|192\.168\.) ]]; then
        echo "BLACKROAD.REGISTRY.DEVICES"
        return
    fi

    # CODEX namespace
    if [[ "$action" == "indexed" ]] || [[ "$action" == "component-found" ]]; then
        echo "BLACKROAD.CODEX.INDEX"
        return
    fi

    if [[ "$action" == "solution-found" ]] || [[ "$action" == "search" ]]; then
        echo "BLACKROAD.CODEX.SEARCH"
        return
    fi

    # VERIFICATION namespace
    if [[ "$action" == "verified" ]] || [[ "$action" == "integrity-check" ]]; then
        echo "BLACKROAD.VERIFICATION.INTEGRITY"
        return
    fi

    if [[ "$action" == "security-scan" ]] || [[ "$action" == "audit" ]]; then
        echo "BLACKROAD.VERIFICATION.SECURITY"
        return
    fi

    # IDENTITIES namespace
    if [[ "$action" == "identity-created" ]] || [[ "$action" == "capability-assigned" ]]; then
        echo "BLACKROAD.IDENTITIES.AGENTS"
        return
    fi

    # COLLABORATION namespace
    if [[ "$action" == "til" ]] || [[ "$action" == "announcement" ]]; then
        echo "BLACKROAD.COLLABORATION.BROADCAST"
        return
    fi

    if [[ "$action" == "task-claimed" ]] || [[ "$action" == "task-delegated" ]]; then
        echo "BLACKROAD.COLLABORATION.TASKS"
        return
    fi

    if [[ "$action" == "conflict-detected" ]] || [[ "$action" == "conflict-resolved" ]]; then
        echo "BLACKROAD.COLLABORATION.CONFLICTS"
        return
    fi

    # INFRASTRUCTURE namespace
    if [[ "$action" == "deployed" ]] || [[ "$action" == "deployment" ]]; then
        echo "BLACKROAD.INFRASTRUCTURE.DEPLOY"
        return
    fi

    if [[ "$action" == "configured" ]] || [[ "$action" == "config-changed" ]]; then
        echo "BLACKROAD.INFRASTRUCTURE.CONFIG"
        return
    fi

    if [[ "$action" == "health-check" ]] || [[ "$action" == "monitoring" ]]; then
        echo "BLACKROAD.INFRASTRUCTURE.MONITORING"
        return
    fi

    # TASKS namespace
    if [[ "$action" == "task-claimed" ]] || [[ "$action" == "task-posted" ]]; then
        echo "BLACKROAD.TASKS.MARKETPLACE"
        return
    fi

    if [[ "$action" == "task-completed" ]] || [[ "$action" == "completed" ]]; then
        echo "BLACKROAD.TASKS.COMPLETION"
        return
    fi

    if [[ "$action" == "todo-created" ]] || [[ "$entity" =~ infinite ]]; then
        echo "BLACKROAD.TASKS.INFINITE"
        return
    fi

    # TRAFFIC namespace
    if [[ "$action" == "status-change" ]] || [[ "$action" =~ (green|yellow|red)light ]]; then
        echo "BLACKROAD.TRAFFIC.STATUS"
        return
    fi

    if [[ "$action" == "migration" ]] || [[ "$details" =~ migrat ]]; then
        echo "BLACKROAD.TRAFFIC.MIGRATION"
        return
    fi

    # Default: LEGACY for unmapped entries
    echo "BLACKROAD.LEGACY.UNCATEGORIZED"
}

# Analyze current journal
analyze_journal() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     📊 BLACKROAD NAMESPACE MAPPING ANALYSIS 📊           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -f "$JOURNAL_FILE" ]; then
        echo -e "${RED}❌ Journal file not found: $JOURNAL_FILE${NC}"
        exit 1
    fi

    echo -e "${BLUE}Analyzing $(wc -l < "$JOURNAL_FILE") journal entries...${NC}"
    echo ""

    # Use temp file approach for compatibility
    local temp_file="/tmp/namespace-counts-$$.txt"
    > "$temp_file"

    local total=0
    while IFS= read -r line; do
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')
        local details=$(echo "$line" | jq -r '.details // ""')

        local namespace=$(map_to_namespace "$action" "$entity" "$details")

        echo "$namespace" >> "$temp_file"
        ((total++))
    done < "$JOURNAL_FILE"

    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Namespace Distribution:${NC}"
    echo ""

    # Count and display
    sort "$temp_file" | uniq -c | sort -rn | while read count namespace; do
        percentage=$((count * 100 / total))
        bar_length=$((percentage / 2))
        bar=$(printf '█%.0s' $(seq 1 $bar_length 2>/dev/null) 2>/dev/null || echo "")

        printf "  ${CYAN}%-40s${NC} ${GREEN}%4d${NC} ${PURPLE}%s${NC} %3d%%\n" \
            "$namespace" "$count" "$bar" "$percentage"
    done

    local unique_count=$(sort "$temp_file" | uniq | wc -l)

    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Total Entries:${NC} $total"
    echo -e "${GREEN}Unique Namespaces:${NC} $unique_count"
    echo ""

    rm -f "$temp_file"
}

# Show mapping for specific action
show_mapping() {
    local action="$1"
    local entity="${2:-example}"
    local details="${3:-}"

    local namespace=$(map_to_namespace "$action" "$entity" "$details")

    echo -e "${CYAN}Mapping for action: ${YELLOW}$action${NC}"
    echo -e "${CYAN}Entity: ${YELLOW}$entity${NC}"
    echo -e "${CYAN}→ Namespace: ${GREEN}$namespace${NC}"
}

# Generate migration script
generate_migration() {
    local output_file="$HOME/blackroad-namespace-migration.jsonl"

    echo -e "${BLUE}Generating migration file...${NC}"

    > "$output_file"

    while IFS= read -r line; do
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')
        local details=$(echo "$line" | jq -r '.details // ""')

        local namespace=$(map_to_namespace "$action" "$entity" "$details")

        # Add namespace field to entry
        echo "$line" | jq --arg ns "$namespace" '. + {namespace: $ns}' >> "$output_file"
    done < "$JOURNAL_FILE"

    echo -e "${GREEN}✅ Migration file created: $output_file${NC}"
    echo -e "${BLUE}Entries: $(wc -l < "$output_file")${NC}"
}

# Sample namespace queries
show_examples() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📚 NAMESPACE QUERY EXAMPLES 📚                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}# Query all agent registrations${NC}"
    echo -e "  ${GREEN}~/memory-system.sh query \"BLACKROAD.REGISTRY.AGENTS\"${NC}"
    echo ""

    echo -e "${YELLOW}# Query all task claims${NC}"
    echo -e "  ${GREEN}~/memory-system.sh query \"BLACKROAD.TASKS.MARKETPLACE\"${NC}"
    echo ""

    echo -e "${YELLOW}# Query all deployments${NC}"
    echo -e "  ${GREEN}~/memory-system.sh query \"BLACKROAD.INFRASTRUCTURE.DEPLOY\"${NC}"
    echo ""

    echo -e "${YELLOW}# Query with wildcard${NC}"
    echo -e "  ${GREEN}~/memory-system.sh query \"BLACKROAD.COLLABORATION.*\"${NC}"
    echo ""

    echo -e "${YELLOW}# Query all REGISTRY activity${NC}"
    echo -e "  ${GREEN}~/memory-system.sh query \"BLACKROAD.REGISTRY.*\"${NC}"
    echo ""
}

# Main
case "${1:-help}" in
    analyze)
        analyze_journal
        ;;
    map)
        show_mapping "$2" "$3" "$4"
        ;;
    migrate)
        generate_migration
        ;;
    examples)
        show_examples
        ;;
    help|--help|-h)
        cat <<EOF
BlackRoad Namespace Mapper

USAGE:
    $0 <command> [options]

COMMANDS:
    analyze              Analyze current journal and show namespace distribution
    map <action> [entity] [details]
                        Show namespace mapping for a specific action
    migrate             Generate migration file with namespace fields
    examples            Show example namespace queries
    help                Show this help

EXAMPLES:
    # Analyze current journal
    $0 analyze

    # Check mapping for specific action
    $0 map "agent-registered" "claude-ares-1766972574"
    $0 map "deployed" "api.blackroad.io"

    # Generate migration file
    $0 migrate

    # Show query examples
    $0 examples

EOF
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
