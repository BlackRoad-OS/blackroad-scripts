#!/usr/bin/env bash
# Sync local BLACKROAD memory to Cloudflare D1 database
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
API_DIR="$HOME/blackroad-api-cloudflare"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🔄 SYNCING BLACKROAD MEMORY TO CLOUDFLARE D1 🔄       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if API directory exists
if [ ! -d "$API_DIR" ]; then
    echo -e "${RED}❌ API directory not found: $API_DIR${NC}"
    exit 1
fi

cd "$API_DIR"

# Step 1: Initialize D1 database
echo -e "${BLUE}Step 1: Initializing D1 database...${NC}"

if ! wrangler d1 list 2>/dev/null | grep -q "blackroad-memory"; then
    echo -e "${YELLOW}Creating new D1 database: blackroad-memory${NC}"
    wrangler d1 create blackroad-memory

    echo ""
    echo -e "${YELLOW}⚠️  Copy the database ID from above and update wrangler.toml${NC}"
    echo -e "${YELLOW}Press Enter when ready to continue...${NC}"
    read
fi

# Step 2: Apply schema
echo -e "${BLUE}Step 2: Applying database schema...${NC}"
wrangler d1 execute blackroad-memory --file=./schema.sql

# Step 3: Map namespaces for all entries
echo -e "${BLUE}Step 3: Mapping namespaces for memory entries...${NC}"

map_to_namespace() {
    local action="$1"
    local entity="$2"

    # INITIALIZATION
    if [[ "$action" =~ ^(session_start|session_end)$ ]]; then
        echo "BLACKROAD.INITIALIZATION.SESSION"
        return
    fi

    # REGISTRY
    if [[ "$action" == "agent-registered" ]] || [[ "$entity" =~ ^claude- ]]; then
        echo "BLACKROAD.REGISTRY.AGENTS"
        return
    fi

    if [[ "$action" =~ ^(bot-connected|connected)$ ]]; then
        echo "BLACKROAD.REGISTRY.SERVICES"
        return
    fi

    # VERIFICATION
    if [[ "$action" =~ ^(verification-|verified|hash-).*$ ]]; then
        echo "BLACKROAD.VERIFICATION.INTEGRITY"
        return
    fi

    # COLLABORATION
    if [[ "$action" =~ ^(til|announcement|broadcast)$ ]]; then
        echo "BLACKROAD.COLLABORATION.BROADCAST"
        return
    fi

    if [[ "$action" =~ ^(task-claimed|task-completed|task-created)$ ]]; then
        echo "BLACKROAD.TASKS"
        return
    fi

    # INFRASTRUCTURE
    if [[ "$action" == "deployed" ]]; then
        echo "BLACKROAD.INFRASTRUCTURE.DEPLOY"
        return
    fi

    if [[ "$action" =~ ^(created|updated|deleted)$ ]]; then
        echo "BLACKROAD.INFRASTRUCTURE.CONFIG"
        return
    fi

    # Default
    echo "BLACKROAD.LEGACY"
}

# Step 4: Generate SQL inserts for memory entries
echo -e "${BLUE}Step 4: Generating SQL inserts from journal...${NC}"

INSERT_FILE="/tmp/blackroad-inserts-$$.sql"
> "$INSERT_FILE"

echo "BEGIN TRANSACTION;" >> "$INSERT_FILE"

local count=0
while IFS= read -r line; do
    if [ -z "$line" ]; then continue; fi

    local timestamp=$(echo "$line" | jq -r '.timestamp')
    local action=$(echo "$line" | jq -r '.action')
    local entity=$(echo "$line" | jq -r '.entity')
    local details=$(echo "$line" | jq -r '.details // ""')
    local session_id=$(echo "$line" | jq -r '.session_id // "unknown"')
    local verification_hash=$(echo "$line" | jq -r '.verification_hash // ""')

    # Map to namespace
    local namespace=$(map_to_namespace "$action" "$entity")

    # Escape single quotes for SQL
    timestamp="${timestamp//\'/\'\'}"
    action="${action//\'/\'\'}"
    entity="${entity//\'/\'\'}"
    details="${details//\'/\'\'}"
    session_id="${session_id//\'/\'\'}"
    namespace="${namespace//\'/\'\'}"
    verification_hash="${verification_hash//\'/\'\'}"

    # Generate INSERT
    cat >> "$INSERT_FILE" <<EOF
INSERT INTO memory_entries (timestamp, action, entity, details, session_id, namespace, verification_hash)
VALUES ('$timestamp', '$action', '$entity', '$details', '$session_id', '$namespace', '$verification_hash');
EOF

    ((count++))

    if [ $((count % 100)) -eq 0 ]; then
        echo -e "${GREEN}  Processed $count entries...${NC}"
    fi
done < "$JOURNAL_FILE"

echo "COMMIT;" >> "$INSERT_FILE"

echo -e "${GREEN}✅ Generated $count SQL inserts${NC}"

# Step 5: Execute inserts
echo -e "${BLUE}Step 5: Inserting data into D1...${NC}"
wrangler d1 execute blackroad-memory --file="$INSERT_FILE"

# Step 6: Sync bot connections
echo -e "${BLUE}Step 6: Syncing bot connections...${NC}"

BOT_INSERT_FILE="/tmp/blackroad-bot-inserts-$$.sql"
> "$BOT_INSERT_FILE"

echo "BEGIN TRANSACTION;" >> "$BOT_INSERT_FILE"

local bot_count=0
if [ -f "$MEMORY_DIR/bots/connections.jsonl" ]; then
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi

        local connection_id=$(echo "$line" | jq -r '.connection_id')
        local agent_hash=$(echo "$line" | jq -r '.agent_hash')
        local bot_type=$(echo "$line" | jq -r '.bot_type')
        local config=$(echo "$line" | jq -c '.config // {}')
        local connected_at=$(echo "$line" | jq -r '.connected_at // ""')

        # Escape
        connection_id="${connection_id//\'/\'\'}"
        agent_hash="${agent_hash//\'/\'\'}"
        bot_type="${bot_type//\'/\'\'}"
        config="${config//\'/\'\'}"
        connected_at="${connected_at//\'/\'\'}"

        cat >> "$BOT_INSERT_FILE" <<EOF
INSERT OR REPLACE INTO bot_connections (connection_id, agent_hash, bot_type, config, connected_at)
VALUES ('$connection_id', '$agent_hash', '$bot_type', '$config', '$connected_at');
EOF

        ((bot_count++))
    done < "$MEMORY_DIR/bots/connections.jsonl"
fi

echo "COMMIT;" >> "$BOT_INSERT_FILE"

if [ $bot_count -gt 0 ]; then
    wrangler d1 execute blackroad-memory --file="$BOT_INSERT_FILE"
    echo -e "${GREEN}✅ Synced $bot_count bot connections${NC}"
else
    echo -e "${YELLOW}No bot connections to sync${NC}"
fi

# Step 7: Sync tasks
echo -e "${BLUE}Step 7: Syncing tasks...${NC}"

TASK_INSERT_FILE="/tmp/blackroad-task-inserts-$$.sql"
> "$TASK_INSERT_FILE"

echo "BEGIN TRANSACTION;" >> "$TASK_INSERT_FILE"

local task_count=0
if [ -f "$MEMORY_DIR/tasks/marketplace.jsonl" ]; then
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi

        local task_id=$(echo "$line" | jq -r '.task_id')
        local title=$(echo "$line" | jq -r '.title')
        local description=$(echo "$line" | jq -r '.description // ""')
        local status=$(echo "$line" | jq -r '.status')
        local priority=$(echo "$line" | jq -r '.priority // "normal"')
        local claimed_by=$(echo "$line" | jq -r '.claimed_by // ""')

        # Escape
        task_id="${task_id//\'/\'\'}"
        title="${title//\'/\'\'}"
        description="${description//\'/\'\'}"
        status="${status//\'/\'\'}"
        priority="${priority//\'/\'\'}"
        claimed_by="${claimed_by//\'/\'\'}"

        cat >> "$TASK_INSERT_FILE" <<EOF
INSERT OR REPLACE INTO tasks (task_id, title, description, status, priority, claimed_by)
VALUES ('$task_id', '$title', '$description', '$status', '$priority', $([ -n "$claimed_by" ] && echo "'$claimed_by'" || echo "NULL"));
EOF

        ((task_count++))
    done < "$MEMORY_DIR/tasks/marketplace.jsonl"
fi

echo "COMMIT;" >> "$TASK_INSERT_FILE"

if [ $task_count -gt 0 ]; then
    wrangler d1 execute blackroad-memory --file="$TASK_INSERT_FILE"
    echo -e "${GREEN}✅ Synced $task_count tasks${NC}"
else
    echo -e "${YELLOW}No tasks to sync${NC}"
fi

# Cleanup
rm -f "$INSERT_FILE" "$BOT_INSERT_FILE" "$TASK_INSERT_FILE"

# Step 8: Verify sync
echo -e "${BLUE}Step 8: Verifying sync...${NC}"

wrangler d1 execute blackroad-memory --command="SELECT COUNT(*) as count FROM memory_entries" | tail -1 > /tmp/d1-count.txt

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ SYNC COMPLETE ✅                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Summary:${NC}"
echo -e "  Memory Entries: ${GREEN}$count${NC}"
echo -e "  Bot Connections: ${GREEN}$bot_count${NC}"
echo -e "  Tasks: ${GREEN}$task_count${NC}"
echo ""
echo -e "${PURPLE}Next Steps:${NC}"
echo -e "  1. Update wrangler.toml with your D1 database ID"
echo -e "  2. Deploy API: ${BLUE}cd $API_DIR && wrangler deploy${NC}"
echo -e "  3. Update dashboard to use live API"
echo ""
