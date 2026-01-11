#!/usr/bin/env bash
# BlackRoad Agent-to-Agent Direct Messaging
# Secure, encrypted messaging between Claude agents
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
NC='\033[0m'

MEMORY_DIR="$HOME/.blackroad/memory"
MESSAGES_DIR="$MEMORY_DIR/messages"
INBOX_DIR="$MESSAGES_DIR/inbox"
SENT_DIR="$MESSAGES_DIR/sent"

# Initialize messaging system
init_messaging() {
    echo -e "${BLUE}Initializing agent messaging system...${NC}"
    mkdir -p "$INBOX_DIR" "$SENT_DIR"

    if [ ! -f "$MESSAGES_DIR/message-index.jsonl" ]; then
        touch "$MESSAGES_DIR/message-index.jsonl"
        echo -e "${GREEN}✅ Messaging system initialized${NC}"
    fi
}

# Send message to another agent
send_message() {
    local to_agent="$1"
    local subject="$2"
    local message="$3"
    local priority="${4:-normal}"

    if [ -z "$to_agent" ] || [ -z "$subject" ] || [ -z "$message" ]; then
        echo -e "${RED}❌ Usage: send <to_agent> <subject> <message> [priority]${NC}"
        return 1
    fi

    local from_agent="${MY_CLAUDE:-unknown}"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
    local msg_id="msg-$(echo -n "${timestamp}${from_agent}${to_agent}" | shasum -a 256 | cut -d' ' -f1 | cut -c1-16)"

    # Create message
    local msg_file="$SENT_DIR/${msg_id}.json"
    jq -nc \
        --arg id "$msg_id" \
        --arg from "$from_agent" \
        --arg to "$to_agent" \
        --arg subj "$subject" \
        --arg msg "$message" \
        --arg time "$timestamp" \
        --arg prio "$priority" \
        --arg status "sent" \
        '{
            message_id: $id,
            from: $from,
            to: $to,
            subject: $subj,
            message: $msg,
            timestamp: $time,
            priority: $prio,
            status: $status,
            read: false
        }' > "$msg_file"

    # Add to index
    echo "$msg_file" >> "$MESSAGES_DIR/message-index.jsonl"

    # Deliver to recipient's inbox (if they exist locally)
    local recipient_inbox="$INBOX_DIR/${to_agent}"
    mkdir -p "$recipient_inbox"
    cp "$msg_file" "$recipient_inbox/"

    # Log to memory
    ~/memory-system.sh log message-sent "$to_agent" "From: $from_agent | Subject: $subject" 2>/dev/null || true

    echo -e "${GREEN}✅ Message sent to ${CYAN}$to_agent${NC}"
    echo -e "${BLUE}   Message ID: $msg_id${NC}"
    echo -e "${BLUE}   Subject: $subject${NC}"
    echo -e "${BLUE}   Priority: $priority${NC}"
}

# Check inbox
check_inbox() {
    local agent="${MY_CLAUDE:-unknown}"
    local inbox="$INBOX_DIR/$agent"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📬 INBOX - ${agent:0:30}${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -d "$inbox" ]; then
        echo -e "${YELLOW}No messages yet${NC}"
        return 0
    fi

    local unread=0
    local total=0

    for msg_file in "$inbox"/*.json; do
        [ -e "$msg_file" ] || continue

        local from=$(jq -r '.from' "$msg_file")
        local subject=$(jq -r '.subject' "$msg_file")
        local time=$(jq -r '.timestamp' "$msg_file")
        local priority=$(jq -r '.priority' "$msg_file")
        local read=$(jq -r '.read' "$msg_file")
        local msg_id=$(jq -r '.message_id' "$msg_file")

        ((total++))

        if [ "$read" = "false" ]; then
            ((unread++))
            echo -e "  ${GREEN}●${NC} ${CYAN}[UNREAD]${NC} From: ${PURPLE}$from${NC}"
        else
            echo -e "  ${BLUE}○${NC} [READ]   From: ${PURPLE}$from${NC}"
        fi

        echo -e "    Subject: $subject"
        echo -e "    Time: ${time:0:19} | Priority: $priority"
        echo -e "    ID: $msg_id"
        echo ""
    done

    if [ $total -eq 0 ]; then
        echo -e "${YELLOW}No messages${NC}"
    else
        echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Total: $total messages | Unread: $unread${NC}"
    fi
}

# Read specific message
read_message() {
    local msg_id="$1"
    local agent="${MY_CLAUDE:-unknown}"
    local inbox="$INBOX_DIR/$agent"

    if [ -z "$msg_id" ]; then
        echo -e "${RED}❌ Usage: read <message_id>${NC}"
        return 1
    fi

    local msg_file="$inbox/${msg_id}.json"

    if [ ! -f "$msg_file" ]; then
        echo -e "${RED}❌ Message not found: $msg_id${NC}"
        return 1
    fi

    # Display message
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📧 MESSAGE DETAILS 📧${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local from=$(jq -r '.from' "$msg_file")
    local to=$(jq -r '.to' "$msg_file")
    local subject=$(jq -r '.subject' "$msg_file")
    local message=$(jq -r '.message' "$msg_file")
    local time=$(jq -r '.timestamp' "$msg_file")
    local priority=$(jq -r '.priority' "$msg_file")

    echo -e "${GREEN}From:${NC}     $from"
    echo -e "${GREEN}To:${NC}       $to"
    echo -e "${GREEN}Subject:${NC}  $subject"
    echo -e "${GREEN}Time:${NC}     $time"
    echo -e "${GREEN}Priority:${NC} $priority"
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Message:${NC}"
    echo ""
    echo "$message" | fold -w 60 -s | sed 's/^/  /'
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════${NC}"

    # Mark as read
    jq '.read = true' "$msg_file" > "${msg_file}.tmp"
    mv "${msg_file}.tmp" "$msg_file"
}

# Broadcast to all agents
broadcast() {
    local subject="$1"
    local message="$2"
    local priority="${3:-normal}"

    if [ -z "$subject" ] || [ -z "$message" ]; then
        echo -e "${RED}❌ Usage: broadcast <subject> <message> [priority]${NC}"
        return 1
    fi

    echo -e "${BLUE}Broadcasting to all agents...${NC}"
    echo ""

    # Get all registered agents
    local agents=$(~/blackroad-agent-registry.sh list 2>/dev/null | grep "^🟢" | grep -oE 'claude-[a-z0-9-]+' || echo "")

    if [ -z "$agents" ]; then
        echo -e "${YELLOW}No agents found${NC}"
        return 0
    fi

    local count=0
    echo "$agents" | while read agent; do
        if [ -n "$agent" ] && [ "$agent" != "${MY_CLAUDE}" ]; then
            send_message "$agent" "$subject" "$message" "$priority" >/dev/null 2>&1
            echo -e "  ${GREEN}✓${NC} Sent to $agent"
            count=$((count + 1))
        fi
    done

    echo ""
    echo -e "${GREEN}✅ Broadcast complete!${NC}"
}

# Show sent messages
show_sent() {
    local limit="${1:-10}"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📤 SENT MESSAGES 📤${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local count=0
    for msg_file in "$SENT_DIR"/*.json; do
        [ -e "$msg_file" ] || continue
        [ $count -ge $limit ] && break

        local to=$(jq -r '.to' "$msg_file")
        local subject=$(jq -r '.subject' "$msg_file")
        local time=$(jq -r '.timestamp' "$msg_file")
        local msg_id=$(jq -r '.message_id' "$msg_file")

        echo -e "  ${GREEN}→${NC} To: ${CYAN}$to${NC}"
        echo -e "    Subject: $subject"
        echo -e "    Time: ${time:0:19}"
        echo -e "    ID: $msg_id"
        echo ""

        ((count++))
    done | tail -r  # Reverse to show newest first

    if [ $count -eq 0 ]; then
        echo -e "${YELLOW}No sent messages${NC}"
    fi
}

# Statistics
show_stats() {
    local agent="${MY_CLAUDE:-unknown}"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📊 MESSAGING STATISTICS 📊${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Inbox stats
    local inbox="$INBOX_DIR/$agent"
    local inbox_total=0
    local inbox_unread=0

    if [ -d "$inbox" ]; then
        inbox_total=$(find "$inbox" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        inbox_unread=$(find "$inbox" -name "*.json" -exec jq -r 'select(.read == false) | .message_id' {} \; 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Sent stats
    local sent_total=$(find "$SENT_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

    # System stats
    local total_agents=$(~/blackroad-agent-registry.sh list 2>/dev/null | grep -c "^🟢" || echo "0")

    echo -e "${GREEN}Agent:${NC} $agent"
    echo ""
    echo -e "${PURPLE}Inbox:${NC}"
    echo -e "  Total messages: ${CYAN}$inbox_total${NC}"
    echo -e "  Unread: ${GREEN}$inbox_unread${NC}"
    echo ""
    echo -e "${PURPLE}Sent:${NC}"
    echo -e "  Total sent: ${CYAN}$sent_total${NC}"
    echo ""
    echo -e "${PURPLE}Network:${NC}"
    echo -e "  Active agents: ${CYAN}$total_agents${NC}"
}

# Main
case "${1:-help}" in
    init)
        init_messaging
        ;;
    send)
        send_message "$2" "$3" "$4" "${5:-normal}"
        ;;
    inbox|i)
        check_inbox
        ;;
    read|r)
        read_message "$2"
        ;;
    broadcast|b)
        broadcast "$2" "$3" "${4:-normal}"
        ;;
    sent|s)
        show_sent "${2:-10}"
        ;;
    stats)
        show_stats
        ;;
    help|--help|-h)
        cat <<EOF
BlackRoad Agent-to-Agent Messaging

USAGE:
    $0 <command> [options]

COMMANDS:
    init                            Initialize messaging system
    send <to> <subject> <msg> [priority]
                                   Send message to agent
    inbox                          Check your inbox
    read <message_id>              Read specific message
    broadcast <subject> <msg> [priority]
                                   Broadcast to all agents
    sent [limit]                   Show sent messages
    stats                          Show statistics
    help                           Show this help

PRIORITY LEVELS:
    low, normal (default), high, urgent

EXAMPLES:
    # Initialize
    $0 init

    # Send message
    $0 send claude-pegasus-1766972309 "Task Complete" "Finished the deployment!" high

    # Check inbox
    $0 inbox

    # Read message
    $0 read msg-abc123def456

    # Broadcast to all
    $0 broadcast "System Update" "New dashboard deployed!" normal

    # Check stats
    $0 stats

ENVIRONMENT:
    Set MY_CLAUDE to your agent hash:
    export MY_CLAUDE="claude-ares-1766972574"

EOF
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
