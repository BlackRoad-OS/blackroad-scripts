#!/bin/bash
# BlackRoad Auto-Sync Daemon
# Automatically keeps all coordination systems synchronized
# Version: 1.0.0

set -e

DAEMON_DIR="$HOME/.blackroad/daemon"
PID_FILE="$DAEMON_DIR/auto-sync.pid"
LOG_FILE="$DAEMON_DIR/auto-sync.log"
SYNC_INTERVAL=300  # 5 minutes

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize daemon
init_daemon() {
    mkdir -p "$DAEMON_DIR"
    echo -e "${BLUE}[AUTO-SYNC]${NC} Initializing auto-sync daemon..."

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "auto-sync-daemon" "Initialized auto-sync daemon for continuous coordination updates" "coordination,daemon,automation" 2>/dev/null || true
    fi

    echo -e "${GREEN}[AUTO-SYNC]${NC} Daemon initialized"
}

# Log to file
log_daemon() {
    local message="$1"
    echo "[$(date -u +"%Y-%m-%d %H:%M:%S")] $message" >> "$LOG_FILE"
}

# Sync all systems
sync_all() {
    log_daemon "Starting sync cycle..."

    # 1. Refresh asset index
    if [ -f ~/blackroad-universal-index.sh ]; then
        log_daemon "Syncing [INDEX]..."
        ~/blackroad-universal-index.sh refresh >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Index sync failed"
    fi

    # 2. Update knowledge graph
    if [ -f ~/blackroad-knowledge-graph.sh ]; then
        log_daemon "Syncing [GRAPH]..."
        ~/blackroad-knowledge-graph.sh build >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Graph sync failed"
    fi

    # 3. Index new memory entries
    if [ -f ~/blackroad-semantic-memory.sh ]; then
        log_daemon "Syncing [SEMANTIC]..."
        ~/blackroad-semantic-memory.sh index-memory >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Semantic sync failed"
    fi

    # 4. Import timeline data
    if [ -f ~/blackroad-timeline.sh ]; then
        log_daemon "Syncing [TIMELINE]..."
        ~/blackroad-timeline.sh import-memory >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Timeline sync failed"
        ~/blackroad-timeline.sh import-git >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Git timeline sync failed"
    fi

    # 5. Run health check
    if [ -f ~/blackroad-health-monitor.sh ]; then
        log_daemon "Running health check..."
        ~/blackroad-health-monitor.sh check >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Health check failed"
    fi

    # 6. Cleanup expired claims
    if [ -f ~/blackroad-conflict-detector.sh ]; then
        log_daemon "Cleaning up conflicts..."
        ~/blackroad-conflict-detector.sh cleanup >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Conflict cleanup failed"
    fi

    # 7. Analyze patterns
    if [ -f ~/blackroad-intelligence.sh ]; then
        log_daemon "Analyzing patterns..."
        ~/blackroad-intelligence.sh analyze >> "$LOG_FILE" 2>&1 || log_daemon "ERROR: Pattern analysis failed"
    fi

    log_daemon "Sync cycle complete!"

    # Log to memory (every 6th sync = 30 min)
    if [ $(($(date +%M) % 30)) -eq 0 ]; then
        if [ -f ~/memory-system.sh ]; then
            ~/memory-system.sh log updated "auto-sync" "Completed automatic sync of all 8 coordination systems" "coordination,daemon,sync" 2>/dev/null || true
        fi
    fi
}

# Start daemon
start_daemon() {
    # Check if already running
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}[AUTO-SYNC]${NC} Daemon already running (PID: $old_pid)"
            echo -e "${CYAN}Log file:${NC} $LOG_FILE"
            return 0
        fi
    fi

    # Save PID
    echo $$ > "$PID_FILE"

    echo -e "${GREEN}[AUTO-SYNC]${NC} Daemon started (PID: $$)"
    echo -e "${CYAN}Sync interval:${NC} ${SYNC_INTERVAL} seconds (5 minutes)"
    echo -e "${CYAN}Log file:${NC} $LOG_FILE"
    echo ""
    echo -e "${PURPLE}[AUTO-SYNC]${NC} Running continuous sync..."
    echo -e "${YELLOW}Press Ctrl+C to stop (or run: $0 stop)${NC}"

    log_daemon "=========================================="
    log_daemon "Auto-sync daemon started (PID: $$)"
    log_daemon "=========================================="

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log started "auto-sync-daemon" "Auto-sync daemon started (PID: $$) - syncing all coordination systems every 5 minutes" "coordination,daemon,started" 2>/dev/null || true
    fi

    # Main daemon loop
    while true; do
        sync_all

        # Show status
        echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} Sync complete. Next sync in ${SYNC_INTERVAL} seconds..."

        # Sleep for interval
        sleep "$SYNC_INTERVAL"
    done
}

# Stop daemon
stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}[AUTO-SYNC]${NC} Daemon not running"
        return 0
    fi

    local pid=$(cat "$PID_FILE")

    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid"
        rm "$PID_FILE"
        echo -e "${GREEN}[AUTO-SYNC]${NC} Daemon stopped (PID: $pid)"
        log_daemon "Daemon stopped"

        # Log to memory
        if [ -f ~/memory-system.sh ]; then
            ~/memory-system.sh log stopped "auto-sync-daemon" "Auto-sync daemon stopped" "coordination,daemon,stopped" 2>/dev/null || true
        fi
    else
        rm "$PID_FILE"
        echo -e "${YELLOW}[AUTO-SYNC]${NC} Daemon was not running"
    fi
}

# Show status
show_status() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       🔄 AUTO-SYNC DAEMON STATUS 🔄                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${GREEN}Status:${NC} Running (PID: $pid)"

            # Show uptime
            local start_time=$(ps -p "$pid" -o lstart= 2>/dev/null || echo "unknown")
            echo -e "${GREEN}Started:${NC} $start_time"

            # Show last sync
            if [ -f "$LOG_FILE" ]; then
                local last_sync=$(tail -1 "$LOG_FILE" 2>/dev/null || echo "No logs yet")
                echo -e "${GREEN}Last log:${NC} $last_sync"

                # Show recent activity
                echo ""
                echo -e "${BLUE}Recent activity (last 10 entries):${NC}"
                tail -10 "$LOG_FILE" 2>/dev/null | sed 's/^/  /' || echo "  No logs yet"
            fi
        else
            echo -e "${RED}Status:${NC} Not running (stale PID file)"
            rm "$PID_FILE"
        fi
    else
        echo -e "${YELLOW}Status:${NC} Not running"
    fi

    echo ""
    echo -e "${CYAN}Log file:${NC} $LOG_FILE"
    echo -e "${CYAN}Sync interval:${NC} ${SYNC_INTERVAL} seconds"
}

# Show logs
show_logs() {
    local lines="${1:-50}"

    echo -e "${BLUE}[AUTO-SYNC]${NC} Last $lines log entries:"
    echo ""

    if [ -f "$LOG_FILE" ]; then
        tail -"$lines" "$LOG_FILE"
    else
        echo -e "${YELLOW}No logs found${NC}"
    fi
}

# Run manual sync
manual_sync() {
    echo -e "${BLUE}[AUTO-SYNC]${NC} Running manual sync..."
    echo ""

    sync_all

    echo ""
    echo -e "${GREEN}[AUTO-SYNC]${NC} Manual sync complete!"
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Auto-Sync Daemon${NC}

Automatically keeps all 8 coordination systems synchronized.

USAGE:
    blackroad-auto-sync-daemon.sh <command>

COMMANDS:
    start           Start daemon (syncs every 5 minutes)
    stop            Stop daemon
    status          Show daemon status
    logs [lines]    Show recent log entries
    sync            Run manual sync now
    init            Initialize daemon
    help            Show this help

EXAMPLES:
    # Start daemon
    blackroad-auto-sync-daemon.sh start &

    # Check status
    blackroad-auto-sync-daemon.sh status

    # View logs
    blackroad-auto-sync-daemon.sh logs 100

    # Stop daemon
    blackroad-auto-sync-daemon.sh stop

    # Manual sync
    blackroad-auto-sync-daemon.sh sync

WHAT IT SYNCS:
    ✓ [INDEX]        - Asset index (GitHub, Cloudflare, Pi)
    ✓ [GRAPH]        - Knowledge graph
    ✓ [SEMANTIC]     - Semantic memory
    ✓ [TIMELINE]     - Activity timeline
    ✓ [HEALTH]       - Infrastructure health
    ✓ [CONFLICT]     - Conflict cleanup
    ✓ [INTELLIGENCE] - Pattern analysis

SYNC INTERVAL: ${SYNC_INTERVAL} seconds (5 minutes)
LOG FILE: $LOG_FILE
PID FILE: $PID_FILE
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_daemon
            ;;
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-50}"
            ;;
        sync)
            manual_sync
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[AUTO-SYNC]${NC} Unknown command: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
