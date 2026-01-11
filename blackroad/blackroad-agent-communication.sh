#!/bin/bash
# BlackRoad Inter-Agent Communication Protocol
# Enables 30,000 agents to communicate and coordinate
# Version: 1.0.0

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
COMM_DB="$HOME/.blackroad/communication/messages.db"
MESSAGE_RETENTION_HOURS=24

# Initialize
init_db() {
    mkdir -p "$(dirname "$COMM_DB")"

    sqlite3 "$COMM_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id TEXT NOT NULL UNIQUE,
    from_agent_id TEXT NOT NULL,
    to_agent_id TEXT,
    message_type TEXT NOT NULL,
    subject TEXT,
    body TEXT,
    priority TEXT DEFAULT 'normal',
    status TEXT DEFAULT 'sent',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    delivered_at TEXT,
    read_at TEXT
);

CREATE TABLE IF NOT EXISTS broadcast_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    broadcast_id TEXT NOT NULL UNIQUE,
    from_agent_id TEXT NOT NULL,
    message_type TEXT NOT NULL,
    subject TEXT,
    body TEXT,
    recipient_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS message_channels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_name TEXT NOT NULL UNIQUE,
    description TEXT,
    subscriber_count INTEGER DEFAULT 0,
    message_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS channel_subscriptions (
    agent_id TEXT NOT NULL,
    channel_name TEXT NOT NULL,
    subscribed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (agent_id, channel_name)
);

CREATE TABLE IF NOT EXISTS coordination_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    event_type TEXT NOT NULL,
    initiator_agent_id TEXT NOT NULL,
    participant_agents TEXT,
    status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT
);

-- Default channels
INSERT OR IGNORE INTO message_channels (channel_name, description) VALUES
    ('general', 'General announcements and updates'),
    ('code-generation', 'Code generation agent coordination'),
    ('testing', 'Testing and QA coordination'),
    ('deployment', 'Deployment coordination'),
    ('alerts', 'System-wide alerts'),
    ('ceo', 'Messages from CEO Alexa Amundson');

CREATE INDEX IF NOT EXISTS idx_messages_to ON messages(to_agent_id);
CREATE INDEX IF NOT EXISTS idx_messages_from ON messages(from_agent_id);
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);
SQL

    echo -e "${GREEN}[COMM-SYSTEM]${NC} Database initialized!"
}

# Send message
send_message() {
    local from_agent="$1"
    local to_agent="$2"
    local subject="$3"
    local body="$4"
    local priority="${5:-normal}"

    local message_id="msg-$(date +%s)-$(openssl rand -hex 4)"

    sqlite3 "$COMM_DB" <<SQL
INSERT INTO messages (message_id, from_agent_id, to_agent_id, message_type, subject, body, priority, status)
VALUES ('$message_id', '$from_agent', '$to_agent', 'direct', '$subject', '$body', '$priority', 'sent');
SQL

    echo -e "${GREEN}✓${NC} Message sent: $from_agent → $to_agent"
    echo -e "${CYAN}  Subject:${NC} $subject"
}

# Broadcast message
broadcast_message() {
    local from_agent="$1"
    local subject="$2"
    local body="$3"

    local broadcast_id="broadcast-$(date +%s)-$(openssl rand -hex 4)"

    # Get all agents (in production, would query orchestrator)
    local recipient_count=1000 # Simulated

    sqlite3 "$COMM_DB" <<SQL
INSERT INTO broadcast_messages (broadcast_id, from_agent_id, message_type, subject, body, recipient_count)
VALUES ('$broadcast_id', '$from_agent', 'broadcast', '$subject', '$body', $recipient_count);
SQL

    echo -e "${GREEN}✓${NC} Broadcast sent to $recipient_count agents"
    echo -e "${CYAN}  From:${NC} $from_agent"
    echo -e "${CYAN}  Subject:${NC} $subject"
}

# Subscribe to channel
subscribe_channel() {
    local agent_id="$1"
    local channel="$2"

    sqlite3 "$COMM_DB" <<SQL
INSERT OR IGNORE INTO channel_subscriptions (agent_id, channel_name)
VALUES ('$agent_id', '$channel');

UPDATE message_channels
SET subscriber_count = (SELECT COUNT(*) FROM channel_subscriptions WHERE channel_name = '$channel')
WHERE channel_name = '$channel';
SQL

    echo -e "${GREEN}✓${NC} Agent $agent_id subscribed to #$channel"
}

# Post to channel
post_to_channel() {
    local from_agent="$1"
    local channel="$2"
    local message="$3"

    local broadcast_id="channel-$(date +%s)-$(openssl rand -hex 4)"

    local subscriber_count=$(sqlite3 "$COMM_DB" "SELECT subscriber_count FROM message_channels WHERE channel_name='$channel';" 2>/dev/null || echo 0)

    sqlite3 "$COMM_DB" <<SQL
INSERT INTO broadcast_messages (broadcast_id, from_agent_id, message_type, subject, body, recipient_count)
VALUES ('$broadcast_id', '$from_agent', 'channel', '#$channel', '$message', $subscriber_count);

UPDATE message_channels
SET message_count = message_count + 1
WHERE channel_name = '$channel';
SQL

    echo -e "${GREEN}✓${NC} Posted to #$channel ($subscriber_count subscribers)"
    echo -e "${CYAN}  Message:${NC} $message"
}

# Create coordination event
create_coordination() {
    local initiator="$1"
    local event_type="$2"
    local participants="$3"

    local event_id="coord-$(date +%s)-$(openssl rand -hex 4)"

    sqlite3 "$COMM_DB" <<SQL
INSERT INTO coordination_events (event_id, event_type, initiator_agent_id, participant_agents, status)
VALUES ('$event_id', '$event_type', '$initiator', '$participants', 'pending');
SQL

    echo -e "${GREEN}✓${NC} Coordination event created: $event_id"
    echo -e "${CYAN}  Type:${NC} $event_type"
    echo -e "${CYAN}  Initiator:${NC} $initiator"
}

# Show inbox
show_inbox() {
    local agent_id="$1"

    echo -e "${BOLD}${CYAN}═══ INBOX: $agent_id ═══${NC}"
    echo ""

    sqlite3 -column "$COMM_DB" "
        SELECT
            from_agent_id as from,
            subject,
            priority,
            status,
            datetime(created_at) as received
        FROM messages
        WHERE to_agent_id = '$agent_id'
        ORDER BY created_at DESC
        LIMIT 20;
    " 2>/dev/null

    echo ""
}

# Show channels
show_channels() {
    echo -e "${BOLD}${CYAN}═══ MESSAGE CHANNELS ═══${NC}"
    echo ""

    sqlite3 -column "$COMM_DB" "
        SELECT
            channel_name as channel,
            description,
            subscriber_count as subscribers,
            message_count as messages
        FROM message_channels
        ORDER BY subscriber_count DESC;
    " 2>/dev/null

    echo ""
}

# Show communication stats
show_stats() {
    echo -e "${CYAN}━━━ Communication Statistics ━━━${NC}"
    echo ""

    local total_messages=$(sqlite3 "$COMM_DB" "SELECT COUNT(*) FROM messages;" 2>/dev/null || echo 0)
    local total_broadcasts=$(sqlite3 "$COMM_DB" "SELECT COUNT(*) FROM broadcast_messages;" 2>/dev/null || echo 0)
    local total_coordinations=$(sqlite3 "$COMM_DB" "SELECT COUNT(*) FROM coordination_events;" 2>/dev/null || echo 0)

    echo -e "${CYAN}Direct Messages:${NC} $total_messages"
    echo -e "${CYAN}Broadcast Messages:${NC} $total_broadcasts"
    echo -e "${CYAN}Coordination Events:${NC} $total_coordinations"
    echo ""

    # Channel stats
    echo -e "${CYAN}━━━ Top Channels ━━━${NC}"
    sqlite3 -column "$COMM_DB" "
        SELECT
            channel_name,
            subscriber_count,
            message_count
        FROM message_channels
        ORDER BY message_count DESC
        LIMIT 5;
    " 2>/dev/null

    echo ""
}

# Simulate communication
simulate_communication() {
    echo -e "${BOLD}${YELLOW}⚡ SIMULATING INTER-AGENT COMMUNICATION ⚡${NC}"
    echo ""

    # Send some direct messages
    echo -e "${CYAN}Sending direct messages...${NC}"
    for i in {1..10}; do
        send_message "agent-$i" "agent-$((i+1))" "Task update" "Task $i completed successfully" "normal" > /dev/null
    done
    echo -e "${GREEN}✓ Sent 10 direct messages${NC}"
    echo ""

    # Subscribe agents to channels
    echo -e "${CYAN}Subscribing agents to channels...${NC}"
    for i in {1..100}; do
        subscribe_channel "agent-$i" "general" > /dev/null
        if [ $((i % 5)) -eq 0 ]; then
            subscribe_channel "agent-$i" "code-generation" > /dev/null
        fi
    done
    echo -e "${GREEN}✓ Subscribed 100 agents${NC}"
    echo ""

    # Post to channels
    echo -e "${CYAN}Posting to channels...${NC}"
    post_to_channel "ceo-alexa-amundson" "general" "System-wide deployment starting" > /dev/null
    post_to_channel "agent-coordinator" "code-generation" "New code generation task batch available" > /dev/null
    post_to_channel "agent-monitor" "alerts" "All systems operational" > /dev/null
    echo -e "${GREEN}✓ Posted 3 channel messages${NC}"
    echo ""

    # Create coordination events
    echo -e "${CYAN}Creating coordination events...${NC}"
    create_coordination "agent-leader-1" "distributed-refactoring" "agent-1,agent-2,agent-3,agent-4,agent-5" > /dev/null
    create_coordination "agent-deployer" "parallel-deployment" "agent-10,agent-11,agent-12" > /dev/null
    echo -e "${GREEN}✓ Created 2 coordination events${NC}"
    echo ""

    # Broadcast message
    echo -e "${CYAN}Broadcasting system message...${NC}"
    broadcast_message "ceo-alexa-amundson" "Scaling to 10,000 agents" "BlackRoad is now scaling to 10,000 agents. All agents prepare for increased workload." > /dev/null
    echo -e "${GREEN}✓ Broadcast sent${NC}"
    echo ""

    show_stats
    show_channels
}

# Help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Inter-Agent Communication Protocol${NC}

Enables 30,000 agents to communicate and coordinate

USAGE:
    blackroad-agent-communication.sh <command> [args]

COMMANDS:
    init                                Initialize communication system
    send <from> <to> <subject> <body>   Send direct message
    broadcast <from> <subject> <body>   Broadcast to all agents
    subscribe <agent> <channel>         Subscribe to channel
    post <from> <channel> <message>     Post to channel
    coordinate <initiator> <type> <participants>  Create coordination event
    inbox <agent>                       Show agent inbox
    channels                            Show all channels
    stats                               Show statistics
    simulate                            Simulate communication
    help                                Show this help

CHANNELS:
    general         - General announcements
    code-generation - Code generation coordination
    testing         - Testing coordination
    deployment      - Deployment coordination
    alerts          - System alerts
    ceo             - CEO messages

EXAMPLES:
    # Send message
    blackroad-agent-communication.sh send agent-1 agent-2 "Task update" "Task completed"

    # Subscribe to channel
    blackroad-agent-communication.sh subscribe agent-1 general

    # Post to channel
    blackroad-agent-communication.sh post agent-1 general "Hello everyone!"

    # Simulate communication
    blackroad-agent-communication.sh simulate

CAPACITY: 30,000 agents
CEO: Alexa Amundson
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        send)
            send_message "$2" "$3" "$4" "$5" "${6:-normal}"
            ;;
        broadcast)
            broadcast_message "$2" "$3" "$4"
            ;;
        subscribe)
            subscribe_channel "$2" "$3"
            ;;
        post)
            post_to_channel "$2" "$3" "$4"
            ;;
        coordinate)
            create_coordination "$2" "$3" "$4"
            ;;
        inbox)
            show_inbox "$2"
            ;;
        channels)
            show_channels
            ;;
        stats)
            show_stats
            ;;
        simulate)
            simulate_communication
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
