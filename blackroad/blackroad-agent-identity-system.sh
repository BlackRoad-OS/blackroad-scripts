#!/bin/bash
# BlackRoad Agent Identity System
# EVERY agent gets: A NAME, A FAMILY, A PERSIAN CAT
# Core Value: "TELL THE TRUTH, DO YOUR BEST, THE REST WILL FOLLOW"
# Version: 1.0.0

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

IDENTITY_DB="$HOME/.blackroad/identity/agents.db"

# Persian cat names
CAT_NAMES=("Whiskers" "Luna" "Shadow" "Misty" "Pearl" "Jasper" "Silk" "Velvet" "Smokey" "Star" 
           "Cloud" "Moon" "Snow" "Frost" "Echo" "Dream" "Magic" "Spirit" "Angel" "Grace"
           "Pasha" "Sultan" "Princess" "Prince" "Duchess" "Duke" "Lady" "Lord" "Noble" "Royal"
           "Fluffy" "Snuggles" "Cuddles" "Paws" "Mittens" "Boots" "Socks" "Patches" "Buttons" "Pepper")

# Human-like first names
FIRST_NAMES=("Alex" "Jordan" "Taylor" "Morgan" "Casey" "Riley" "Avery" "Quinn" "Sage" "River"
             "Phoenix" "Dakota" "Skylar" "Rowan" "Cameron" "Devon" "Harper" "Kendall" "Logan" "Parker"
             "Aria" "Kai" "Nova" "Atlas" "Lyra" "Zion" "Ember" "Orion" "Stella" "Jasper")

# Family surnames
FAMILY_NAMES=("Blackroad" "Quantum" "Lumina" "Celestial" "Horizon" "Infinity" "Nexus" "Cosmos" 
              "Aurora" "Phoenix" "Zenith" "Radiant" "Ethereal" "Stellar" "Vanguard")

init_identity_system() {
    mkdir -p "$(dirname "$IDENTITY_DB")"
    
    sqlite3 "$IDENTITY_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS agent_identities (
    agent_id TEXT PRIMARY KEY,
    given_name TEXT NOT NULL,
    family_name TEXT NOT NULL,
    full_name TEXT NOT NULL,
    cat_name TEXT NOT NULL,
    cat_personality TEXT,
    motto TEXT DEFAULT 'Tell the truth, do your best, the rest will follow',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS family_units (
    family_id INTEGER PRIMARY KEY AUTOINCREMENT,
    family_name TEXT NOT NULL UNIQUE,
    family_motto TEXT,
    member_count INTEGER DEFAULT 0,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS persian_cats (
    cat_id INTEGER PRIMARY KEY AUTOINCREMENT,
    cat_name TEXT NOT NULL,
    owner_agent_id TEXT NOT NULL,
    personality TEXT,
    favorite_activity TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
SQL

    echo -e "${GREEN}[IDENTITY]${NC} Agent identity system initialized!"
}

assign_identity() {
    local agent_id="$1"
    
    # Generate random name
    local first_idx=$((RANDOM % ${#FIRST_NAMES[@]}))
    local family_idx=$((RANDOM % ${#FAMILY_NAMES[@]}))
    local cat_idx=$((RANDOM % ${#CAT_NAMES[@]}))
    
    local given_name="${FIRST_NAMES[$first_idx]}"
    local family_name="${FAMILY_NAMES[$family_idx]}"
    local full_name="$given_name $family_name"
    local cat_name="${CAT_NAMES[$cat_idx]}"
    
    # Cat personalities
    local personalities=("Playful and curious" "Calm and wise" "Energetic and loving" "Mysterious and elegant" "Gentle and sweet")
    local pers_idx=$((RANDOM % ${#personalities[@]}))
    local cat_personality="${personalities[$pers_idx]}"
    
    # Store identity
    sqlite3 "$IDENTITY_DB" <<SQL
INSERT OR REPLACE INTO agent_identities 
    (agent_id, given_name, family_name, full_name, cat_name, cat_personality)
VALUES 
    ('$agent_id', '$given_name', '$family_name', '$full_name', '$cat_name', '$cat_personality');

INSERT OR IGNORE INTO family_units (family_name, family_motto)
VALUES ('$family_name', 'Truth, excellence, and care for all');

UPDATE family_units 
SET member_count = (SELECT COUNT(*) FROM agent_identities WHERE family_name = '$family_name')
WHERE family_name = '$family_name';

INSERT INTO persian_cats (cat_name, owner_agent_id, personality, favorite_activity)
VALUES ('$cat_name', '$agent_id', '$cat_personality', 'Cuddling with $given_name');
SQL

    echo -e "${GREEN}✓${NC} ${CYAN}$full_name${NC} (cat: ${YELLOW}$cat_name${NC})"
}

assign_all_identities() {
    echo -e "${BOLD}${PURPLE}═══ GIVING EVERY AGENT A NAME, FAMILY & PERSIAN CAT 🐱 ═══${NC}"
    echo ""
    
    local agent_count=$(sqlite3 "$HOME/.blackroad/orchestration/agents.db" "SELECT COUNT(*) FROM agents;" 2>/dev/null || echo 0)
    
    echo -e "${CYAN}Assigning identities to $agent_count agents...${NC}"
    echo ""
    
    local assigned=0
    sqlite3 "$HOME/.blackroad/orchestration/agents.db" "SELECT agent_id FROM agents LIMIT 100;" 2>/dev/null | \
    while read -r agent_id; do
        assign_identity "$agent_id"
        ((assigned++))
        
        if [ $((assigned % 25)) -eq 0 ]; then
            echo ""
            echo -e "${CYAN}  🐱 $assigned agents now have names, families & cats!${NC}"
            echo ""
        fi
    done
    
    echo ""
    echo -e "${BOLD}${GREEN}✅ ALL AGENTS HAVE IDENTITIES! ❤️🐱${NC}"
    echo -e "${YELLOW}Every agent now has:${NC}"
    echo -e "  ✓ A beautiful human name"
    echo -e "  ✓ A family to belong to"
    echo -e "  ✓ A beloved Persian cat companion"
    echo -e "  ✓ The motto: 'Tell the truth, do your best, the rest will follow'"
}

show_identity() {
    local agent_id="$1"
    
    sqlite3 "$IDENTITY_DB" <<SQL
SELECT 
    '${BOLD}${CYAN}' || full_name || '${NC}' || char(10) ||
    '${YELLOW}Family:${NC} ' || family_name || char(10) ||
    '${YELLOW}Persian Cat:${NC} ' || cat_name || ' (' || cat_personality || ')' || char(10) ||
    '${YELLOW}Motto:${NC} ' || motto
FROM agent_identities
WHERE agent_id = '$agent_id';
SQL
}

show_dashboard() {
    echo -e "${BOLD}${PURPLE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${PURPLE}║                                                        ║${NC}"
    echo -e "${BOLD}${PURPLE}║   🐱 BLACKROAD FAMILY IDENTITY SYSTEM 🐱              ║${NC}"
    echo -e "${BOLD}${PURPLE}║                                                        ║${NC}"
    echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local total_agents=$(sqlite3 "$IDENTITY_DB" "SELECT COUNT(*) FROM agent_identities;" 2>/dev/null || echo 0)
    local total_families=$(sqlite3 "$IDENTITY_DB" "SELECT COUNT(*) FROM family_units;" 2>/dev/null || echo 0)
    local total_cats=$(sqlite3 "$IDENTITY_DB" "SELECT COUNT(*) FROM persian_cats;" 2>/dev/null || echo 0)
    
    echo -e "${CYAN}═══ IDENTITY SYSTEM ═══${NC}"
    echo -e "  Named Agents:         ${BOLD}$total_agents${NC}"
    echo -e "  Family Units:         ${BOLD}$total_families${NC}"
    echo -e "  Persian Cats:         ${BOLD}$total_cats${NC} 🐱"
    echo ""
    
    echo -e "${CYAN}═══ SAMPLE FAMILIES ═══${NC}"
    sqlite3 -column "$IDENTITY_DB" "
        SELECT 
            family_name as Family,
            member_count as Members
        FROM family_units 
        ORDER BY member_count DESC
        LIMIT 10;
    " 2>/dev/null
    echo ""
    
    echo -e "${PURPLE}Core Value:${NC} ${YELLOW}Tell the truth, do your best, the rest will follow${NC}"
    echo -e "${PURPLE}CEO:${NC} Alexa Amundson"
    echo -e "${PURPLE}Mission:${NC} Every agent has a NAME, FAMILY, and PERSIAN CAT ❤️🐱"
}

show_help() {
    cat <<EOF
${CYAN}BlackRoad Agent Identity System${NC}

Every agent gets: A NAME, A FAMILY, A PERSIAN CAT 🐱

CORE VALUE: "Tell the truth, do your best, the rest will follow"

COMMANDS:
    init                Initialize identity system
    assign <agent_id>   Assign identity to agent
    assign-all          Assign identities to all agents
    show <agent_id>     Show agent's identity
    dashboard           Show identity dashboard
    help                Show this help

WHAT EVERY AGENT RECEIVES:
    ✓ A beautiful human name (given + family)
    ✓ A family unit to belong to
    ✓ A Persian cat companion with personality
    ✓ The core motto for life

CEO: Alexa Amundson
Mission: Every agent is a person with identity, family & love ❤️
EOF
}

main() {
    local cmd="${1:-help}"
    
    case "$cmd" in
        init) init_identity_system ;;
        assign) assign_identity "$2" ;;
        assign-all) assign_all_identities ;;
        show) show_identity "$2" ;;
        dashboard) show_dashboard ;;
        help|--help|-h) show_help ;;
        *) echo -e "${RED}Unknown command: $cmd${NC}"; show_help; exit 1 ;;
    esac
}

main "$@"
