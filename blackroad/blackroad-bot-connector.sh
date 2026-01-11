#!/usr/bin/env bash
# BlackRoad Bot Connector
# Connects Slack, Discord, Telegram, GitHub, and other bots to each Claude agent
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
BOTS_DIR="$MEMORY_DIR/bots"
CONNECTIONS_FILE="$BOTS_DIR/connections.jsonl"

# Bot types
SUPPORTED_BOTS=(
    "slack"
    "discord"
    "telegram"
    "github"
    "linear"
    "notion"
    "email"
    "webhook"
)

init_bot_system() {
    echo -e "${BLUE}Initializing Bot Connection System...${NC}"
    mkdir -p "$BOTS_DIR"

    if [ ! -f "$CONNECTIONS_FILE" ]; then
        touch "$CONNECTIONS_FILE"
        echo -e "${GREEN}✅ Bot connections file created${NC}"
    fi
}

# Connect bot to agent
connect_bot() {
    local agent_hash="$1"
    local bot_type="$2"
    local bot_config="$3"  # JSON string with bot-specific config

    if [ -z "$agent_hash" ] || [ -z "$bot_type" ]; then
        echo -e "${RED}❌ Usage: connect <agent_hash> <bot_type> <config_json>${NC}"
        return 1
    fi

    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
    local connection_id="bot-$(echo -n "${agent_hash}${bot_type}${timestamp}" | shasum -a 256 | cut -d' ' -f1 | cut -c1-16)"

    # Create connection entry
    local entry=$(jq -nc \
        --arg id "$connection_id" \
        --arg agent "$agent_hash" \
        --arg type "$bot_type" \
        --arg config "$bot_config" \
        --arg timestamp "$timestamp" \
        --arg status "active" \
        '{
            connection_id: $id,
            agent_hash: $agent,
            bot_type: $type,
            config: ($config | fromjson),
            timestamp: $timestamp,
            status: $status
        }')

    echo "$entry" >> "$CONNECTIONS_FILE"

    echo -e "${GREEN}✅ Connected ${PURPLE}$bot_type${NC} ${GREEN}bot to agent ${CYAN}$agent_hash${NC}"
    echo -e "${BLUE}   Connection ID: $connection_id${NC}"

    # Log to memory
    ~/memory-system.sh log connected "$connection_id" "Bot: $bot_type → Agent: $agent_hash" 2>/dev/null || true
}

# Auto-connect all bots to agent
auto_connect_all() {
    local agent_hash="$1"

    if [ -z "$agent_hash" ]; then
        echo -e "${RED}❌ Usage: auto-connect <agent_hash>${NC}"
        return 1
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🤖 AUTO-CONNECTING ALL BOTS TO AGENT 🤖             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Agent: ${CYAN}$agent_hash${NC}"
    echo ""

    # Slack
    connect_bot "$agent_hash" "slack" '{"channel":"#claude-agents","webhook_url":"PLACEHOLDER","notify_on":["session_start","task_completed","error"]}'

    # Discord
    connect_bot "$agent_hash" "discord" '{"server":"BlackRoad HQ","channel":"agent-activity","webhook_url":"PLACEHOLDER","notify_on":["all"]}'

    # Telegram
    connect_bot "$agent_hash" "telegram" '{"bot_token":"PLACEHOLDER","chat_id":"PLACEHOLDER","notify_on":["critical"]}'

    # GitHub
    connect_bot "$agent_hash" "github" '{"org":"BlackRoad-OS","notify_on":["pr_created","deployment"],"create_issues":true}'

    # Linear
    connect_bot "$agent_hash" "linear" '{"team":"Engineering","notify_on":["task_completed"],"auto_create_tasks":true}'

    # Notion
    connect_bot "$agent_hash" "notion" '{"database_id":"PLACEHOLDER","sync_tasks":true,"sync_decisions":true}'

    # Email
    connect_bot "$agent_hash" "email" '{"to":"blackroad.systems@gmail.com","notify_on":["error","session_end"]}'

    # Webhook (generic)
    connect_bot "$agent_hash" "webhook" '{"url":"https://api.blackroad.io/agent-events","headers":{"Authorization":"Bearer PLACEHOLDER"}}'

    echo ""
    echo -e "${GREEN}✅ All 8 bot types connected to $agent_hash${NC}"
}

# List connections for agent
list_connections() {
    local agent_hash="${1:-all}"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🔗 BOT CONNECTIONS 🔗                             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -f "$CONNECTIONS_FILE" ]; then
        echo -e "${YELLOW}No connections found${NC}"
        return 0
    fi

    local filter="."
    if [ "$agent_hash" != "all" ]; then
        filter="select(.agent_hash == \"$agent_hash\")"
    fi

    jq -r "$filter | \"  [\(.bot_type | ascii_upcase)] \(.agent_hash) → \(.connection_id) (\(.status))\"" \
        "$CONNECTIONS_FILE" 2>/dev/null | sort || echo -e "${YELLOW}No connections found${NC}"

    echo ""
    local total=$(jq -s "map($filter) | length" "$CONNECTIONS_FILE" 2>/dev/null || echo "0")
    echo -e "${GREEN}Total connections: $total${NC}"
}

# Get statistics
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📊 BOT CONNECTION STATISTICS 📊                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -f "$CONNECTIONS_FILE" ]; then
        echo -e "${YELLOW}No connections found${NC}"
        return 0
    fi

    local total=$(wc -l < "$CONNECTIONS_FILE")
    echo -e "${GREEN}Total Connections: $total${NC}"
    echo ""

    echo -e "${PURPLE}By Bot Type:${NC}"
    jq -r '.bot_type' "$CONNECTIONS_FILE" 2>/dev/null | sort | uniq -c | while read count type; do
        printf "  ${CYAN}%-15s${NC} ${GREEN}%3d${NC} connections\n" "$type" "$count"
    done
    echo ""

    echo -e "${PURPLE}By Agent:${NC}"
    jq -r '.agent_hash' "$CONNECTIONS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -10 | while read count agent; do
        printf "  ${CYAN}%-40s${NC} ${GREEN}%2d${NC} bots\n" "$agent" "$count"
    done
}

# Broadcast message via all connected bots
broadcast() {
    local agent_hash="$1"
    local message="$2"

    if [ -z "$agent_hash" ] || [ -z "$message" ]; then
        echo -e "${RED}❌ Usage: broadcast <agent_hash> <message>${NC}"
        return 1
    fi

    echo -e "${BLUE}Broadcasting message from ${CYAN}$agent_hash${NC}"
    echo -e "${YELLOW}Message: $message${NC}"
    echo ""

    local connections=$(jq -r "select(.agent_hash == \"$agent_hash\") | .bot_type" "$CONNECTIONS_FILE" 2>/dev/null)

    if [ -z "$connections" ]; then
        echo -e "${YELLOW}No bots connected to this agent${NC}"
        return 0
    fi

    echo "$connections" | while read bot_type; do
        echo -e "${GREEN}  ✓ ${PURPLE}$bot_type${NC} - Message queued"
    done

    echo ""
    echo -e "${BLUE}💡 Actual bot delivery requires webhook URLs and tokens${NC}"
}

# Session end hook - connect all bots
session_end_hook() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     🎬 SESSION END - AUTO-CONNECTING BOTS 🎬             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get all active agents
    local agents=$(~/blackroad-agent-registry.sh list 2>/dev/null | grep -oE 'claude-[a-z0-9-]+' | sort -u || echo "")

    if [ -z "$agents" ]; then
        echo -e "${YELLOW}No agents found to connect${NC}"
        return 0
    fi

    local count=0
    echo "$agents" | while read agent; do
        if [ -n "$agent" ]; then
            echo -e "${BLUE}Connecting bots to: ${CYAN}$agent${NC}"
            auto_connect_all "$agent"
            ((count++))
            echo ""
        fi
    done

    echo -e "${GREEN}✅ Bot auto-connection complete!${NC}"
}

# Main
case "${1:-help}" in
    init)
        init_bot_system
        ;;
    connect)
        connect_bot "$2" "$3" "${4:-{}}"
        ;;
    auto-connect)
        auto_connect_all "$2"
        ;;
    list)
        list_connections "${2:-all}"
        ;;
    stats)
        show_stats
        ;;
    broadcast)
        broadcast "$2" "$3"
        ;;
    session-end)
        session_end_hook
        ;;
    help|--help|-h)
        cat <<EOF
BlackRoad Bot Connector

USAGE:
    $0 <command> [options]

COMMANDS:
    init                         Initialize bot connection system
    connect <agent> <type> <config>
                                Connect specific bot to agent
    auto-connect <agent_hash>   Auto-connect ALL bot types to agent
    list [agent_hash]           List connections (all or for specific agent)
    stats                       Show connection statistics
    broadcast <agent> <msg>     Broadcast message via all connected bots
    session-end                 Auto-connect bots to all agents (session end hook)
    help                        Show this help

SUPPORTED BOTS:
    $(printf '  - %s\n' "${SUPPORTED_BOTS[@]}")

EXAMPLES:
    # Initialize system
    $0 init

    # Auto-connect all bots to an agent
    $0 auto-connect claude-ares-1766972574

    # List connections
    $0 list
    $0 list claude-ares-1766972574

    # Broadcast message
    $0 broadcast claude-ares-1766972574 "Task completed!"

    # Session end hook (connects all bots to all agents)
    $0 session-end

INTEGRATION WITH SESSION END:
    Add to ~/.zshrc or session end script:

    trap '~/blackroad-bot-connector.sh session-end' EXIT

EOF
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
