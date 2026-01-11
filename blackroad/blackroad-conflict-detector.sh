#!/bin/bash
# [CONFLICT] - BlackRoad Automatic Conflict Detector
# Prevents Claude agents from stepping on each other
# Version: 1.0.0

set -e

CONFLICT_DIR="$HOME/.blackroad/conflict"
CONFLICT_DB="$CONFLICT_DIR/locks.db"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize conflict detection
init_conflict() {
    echo -e "${BLUE}[CONFLICT]${NC} Initializing conflict detection system..."

    mkdir -p "$CONFLICT_DIR"

    # Create database for work claims and locks
    sqlite3 "$CONFLICT_DB" <<EOF
CREATE TABLE IF NOT EXISTS work_claims (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    resource TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    description TEXT,
    claimed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    expires_at TEXT,
    status TEXT DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS file_locks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    operation TEXT,
    locked_at TEXT DEFAULT CURRENT_TIMESTAMP,
    released_at TEXT
);

CREATE TABLE IF NOT EXISTS conflict_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    resource TEXT NOT NULL,
    agent1_id TEXT NOT NULL,
    agent2_id TEXT NOT NULL,
    conflict_type TEXT NOT NULL,
    resolved BOOLEAN DEFAULT 0,
    resolution TEXT,
    detected_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_claims_resource ON work_claims(resource);
CREATE INDEX IF NOT EXISTS idx_claims_agent ON work_claims(agent_id);
CREATE INDEX IF NOT EXISTS idx_claims_status ON work_claims(status);
CREATE INDEX IF NOT EXISTS idx_locks_file ON file_locks(file_path);
CREATE INDEX IF NOT EXISTS idx_conflicts_resource ON conflict_events(resource);
EOF

    echo -e "${GREEN}[CONFLICT]${NC} Conflict detection initialized at: $CONFLICT_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "conflict-detector" "Initialized [CONFLICT] automatic conflict detection system" "coordination,conflict,detection" 2>/dev/null || true
    fi
}

# Claim work on a resource
claim_work() {
    local resource="$1"
    local description="$2"
    local agent_id="${MY_CLAUDE:-unknown-agent}"
    local resource_type="repository"

    if [ -z "$resource" ]; then
        echo -e "${RED}[CONFLICT]${NC} Resource name required"
        return 1
    fi

    # Check if someone else has an active claim
    local existing_claim=$(sqlite3 "$CONFLICT_DB" "
        SELECT agent_id, description, claimed_at
        FROM work_claims
        WHERE resource='${resource}' AND status='active' AND agent_id!='${agent_id}'
        LIMIT 1;
    " | head -1)

    if [ -n "$existing_claim" ]; then
        local other_agent=$(echo "$existing_claim" | cut -d'|' -f1)
        local other_desc=$(echo "$existing_claim" | cut -d'|' -f2)
        local claimed_time=$(echo "$existing_claim" | cut -d'|' -f3)

        echo -e "${RED}[CONFLICT]${NC} ⚠️  CONFLICT DETECTED!"
        echo -e "${YELLOW}Resource:${NC} $resource"
        echo -e "${YELLOW}Already claimed by:${NC} $other_agent"
        echo -e "${YELLOW}Working on:${NC} $other_desc"
        echo -e "${YELLOW}Since:${NC} $claimed_time"
        echo ""
        echo -e "${CYAN}Suggestion:${NC} Coordinate with $other_agent or work on different resource"

        # Log conflict event
        sqlite3 "$CONFLICT_DB" <<EOF
INSERT INTO conflict_events (resource, agent1_id, agent2_id, conflict_type)
VALUES ('${resource}', '${other_agent}', '${agent_id}', 'work_claim_collision');
EOF

        # Alert to memory
        if [ -f ~/memory-system.sh ]; then
            ~/memory-system.sh log alert "conflict-detected" "CONFLICT: $agent_id tried to claim $resource but $other_agent already working on it!" "coordination,conflict,alert" 2>/dev/null || true
        fi

        return 1
    fi

    # Claim the resource
    local expires_at=$(date -u -v+4H +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -u -d "+4 hours" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date -u +"%Y-%m-%d %H:%M:%S")

    sqlite3 "$CONFLICT_DB" <<EOF
INSERT INTO work_claims (resource, resource_type, agent_id, description, expires_at)
VALUES ('${resource}', '${resource_type}', '${agent_id}', '${description}', '${expires_at}');
EOF

    echo -e "${GREEN}[CONFLICT]${NC} ✓ Work claimed successfully!"
    echo -e "${CYAN}Resource:${NC} $resource"
    echo -e "${CYAN}Agent:${NC} $agent_id"
    echo -e "${CYAN}Task:${NC} $description"
    echo -e "${CYAN}Expires:${NC} $expires_at"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log collaboration "work-claim" "$agent_id claimed $resource: $description" "coordination,conflict,claim" 2>/dev/null || true
    fi
}

# Release work claim
release_work() {
    local resource="$1"
    local agent_id="${MY_CLAUDE:-unknown-agent}"

    if [ -z "$resource" ]; then
        echo -e "${RED}[CONFLICT]${NC} Resource name required"
        return 1
    fi

    # Check if we have a claim
    local claim_exists=$(sqlite3 "$CONFLICT_DB" "
        SELECT COUNT(*) FROM work_claims
        WHERE resource='${resource}' AND agent_id='${agent_id}' AND status='active';
    ")

    if [ "$claim_exists" -eq 0 ]; then
        echo -e "${YELLOW}[CONFLICT]${NC} No active claim found for $resource"
        return 1
    fi

    # Release the claim
    sqlite3 "$CONFLICT_DB" "
        UPDATE work_claims
        SET status='completed'
        WHERE resource='${resource}' AND agent_id='${agent_id}' AND status='active';
    "

    echo -e "${GREEN}[CONFLICT]${NC} ✓ Work claim released for: $resource"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log collaboration "work-release" "$agent_id released $resource" "coordination,conflict,release" 2>/dev/null || true
    fi
}

# Check for conflicts before working on resource
check_conflicts() {
    local resource="$1"
    local agent_id="${MY_CLAUDE:-unknown-agent}"

    if [ -z "$resource" ]; then
        echo -e "${RED}[CONFLICT]${NC} Resource name required"
        return 1
    fi

    # Check for active claims
    local active_claims=$(sqlite3 "$CONFLICT_DB" "
        SELECT agent_id, description, claimed_at
        FROM work_claims
        WHERE resource='${resource}' AND status='active'
        ORDER BY claimed_at;
    ")

    if [ -z "$active_claims" ]; then
        echo -e "${GREEN}[CONFLICT]${NC} ✓ No conflicts - resource available!"
        echo -e "${CYAN}Resource:${NC} $resource"
        echo -e "${CYAN}Status:${NC} Available for work"
        return 0
    fi

    echo -e "${BLUE}[CONFLICT]${NC} Active work on: $resource"
    echo ""

    local conflict_detected=0

    echo "$active_claims" | while IFS='|' read -r other_agent desc claimed_time; do
        if [ "$other_agent" = "$agent_id" ]; then
            echo -e "${GREEN}  ✓${NC} Your claim: $desc (since $claimed_time)"
        else
            echo -e "${YELLOW}  ⚠${NC} $other_agent working on: $desc (since $claimed_time)"
            conflict_detected=1
        fi
    done

    if [ $conflict_detected -eq 1 ]; then
        echo ""
        echo -e "${YELLOW}[CONFLICT]${NC} ⚠️  Other agents are working on this resource!"
        echo -e "${CYAN}Recommendation:${NC} Coordinate before proceeding"
        return 1
    fi

    return 0
}

# Show all active claims
show_active() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ⚠️  ACTIVE WORK CLAIMS ⚠️                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_claims=$(sqlite3 "$CONFLICT_DB" "SELECT COUNT(*) FROM work_claims WHERE status='active';")

    if [ "$total_claims" -eq 0 ]; then
        echo -e "${GREEN}✓ No active work claims${NC}"
        echo -e "${CYAN}All resources available for work!${NC}"
        return 0
    fi

    echo -e "${YELLOW}Total Active Claims:${NC} $total_claims"
    echo ""

    sqlite3 -column -header "$CONFLICT_DB" <<EOF
SELECT
    resource,
    agent_id as agent,
    substr(description, 1, 40) as task,
    substr(claimed_at, 1, 16) as claimed,
    substr(expires_at, 1, 16) as expires
FROM work_claims
WHERE status='active'
ORDER BY claimed_at DESC;
EOF
}

# Show my claims
show_my_claims() {
    local agent_id="${MY_CLAUDE:-unknown-agent}"

    echo -e "${BLUE}[CONFLICT]${NC} My active work claims:"
    echo ""

    local my_claims=$(sqlite3 "$CONFLICT_DB" "
        SELECT COUNT(*) FROM work_claims
        WHERE agent_id='${agent_id}' AND status='active';
    ")

    if [ "$my_claims" -eq 0 ]; then
        echo -e "${YELLOW}No active claims${NC}"
        echo -e "${CYAN}Tip: Claim work before starting with: claim <resource> \"description\"${NC}"
        return 0
    fi

    sqlite3 -column -header "$CONFLICT_DB" <<EOF
SELECT
    resource,
    description,
    substr(claimed_at, 1, 16) as claimed,
    substr(expires_at, 1, 16) as expires
FROM work_claims
WHERE agent_id='${agent_id}' AND status='active'
ORDER BY claimed_at DESC;
EOF
}

# Show conflict history
show_conflicts() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║            📊 CONFLICT HISTORY 📊                      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_conflicts=$(sqlite3 "$CONFLICT_DB" "SELECT COUNT(*) FROM conflict_events;")
    local unresolved=$(sqlite3 "$CONFLICT_DB" "SELECT COUNT(*) FROM conflict_events WHERE resolved=0;")

    echo -e "${YELLOW}Total Conflicts:${NC} $total_conflicts"
    echo -e "${RED}Unresolved:${NC}      $unresolved"
    echo ""

    if [ "$total_conflicts" -eq 0 ]; then
        echo -e "${GREEN}✓ No conflicts detected!${NC}"
        echo -e "${CYAN}Great collaboration!${NC}"
        return 0
    fi

    echo -e "${BLUE}Recent Conflicts:${NC}"
    sqlite3 -column -header "$CONFLICT_DB" <<EOF
SELECT
    resource,
    agent1_id || ' vs ' || agent2_id as agents,
    conflict_type as type,
    CASE WHEN resolved=1 THEN '✓' ELSE '⚠' END as status,
    substr(detected_at, 1, 16) as when
FROM conflict_events
ORDER BY detected_at DESC
LIMIT 10;
EOF
}

# Clean up expired claims
cleanup_expired() {
    echo -e "${BLUE}[CONFLICT]${NC} Cleaning up expired claims..."

    local expired_count=$(sqlite3 "$CONFLICT_DB" "
        SELECT COUNT(*) FROM work_claims
        WHERE status='active' AND datetime(expires_at) < datetime('now');
    ")

    if [ "$expired_count" -eq 0 ]; then
        echo -e "${GREEN}[CONFLICT]${NC} No expired claims to clean up"
        return 0
    fi

    sqlite3 "$CONFLICT_DB" "
        UPDATE work_claims
        SET status='expired'
        WHERE status='active' AND datetime(expires_at) < datetime('now');
    "

    echo -e "${GREEN}[CONFLICT]${NC} Cleaned up $expired_count expired claims"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "conflict-cleanup" "Cleaned up $expired_count expired work claims" "coordination,conflict,cleanup" 2>/dev/null || true
    fi
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Automatic Conflict Detector [CONFLICT]${NC}

USAGE:
    blackroad-conflict-detector.sh <command> [options]

COMMANDS:
    init                        Initialize conflict detection
    claim <resource> <desc>     Claim work on resource
    release <resource>          Release work claim
    check <resource>            Check for conflicts
    active                      Show all active claims
    mine                        Show my claims
    conflicts                   Show conflict history
    cleanup                     Clean up expired claims
    help                        Show this help

EXAMPLES:
    # Initialize
    blackroad-conflict-detector.sh init

    # Before starting work
    blackroad-conflict-detector.sh check blackroad-os-dashboard

    # Claim work
    blackroad-conflict-detector.sh claim blackroad-os-dashboard "Adding new authentication"

    # Check what others are working on
    blackroad-conflict-detector.sh active

    # When done
    blackroad-conflict-detector.sh release blackroad-os-dashboard

    # View my claims
    blackroad-conflict-detector.sh mine

    # View conflict history
    blackroad-conflict-detector.sh conflicts

ENVIRONMENT:
    MY_CLAUDE - Your Claude agent ID (required)
    export MY_CLAUDE="claude-your-name-\$(date +%s)"

DATABASE: $CONFLICT_DB
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_conflict
            ;;
        claim)
            if [ -z "$2" ]; then
                echo -e "${RED}[CONFLICT]${NC} Usage: claim <resource> <description>"
                exit 1
            fi
            claim_work "$2" "${3:-Working on this resource}"
            ;;
        release)
            if [ -z "$2" ]; then
                echo -e "${RED}[CONFLICT]${NC} Usage: release <resource>"
                exit 1
            fi
            release_work "$2"
            ;;
        check)
            if [ -z "$2" ]; then
                echo -e "${RED}[CONFLICT]${NC} Usage: check <resource>"
                exit 1
            fi
            check_conflicts "$2"
            ;;
        active)
            show_active
            ;;
        mine)
            show_my_claims
            ;;
        conflicts)
            show_conflicts
            ;;
        cleanup)
            cleanup_expired
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[CONFLICT]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
