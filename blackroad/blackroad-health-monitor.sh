#!/bin/bash
# [HEALTH] - BlackRoad Infrastructure Health Monitor
# Real-time health monitoring across ALL infrastructure
# Version: 1.0.0

set -e

HEALTH_DIR="$HOME/.blackroad/health"
HEALTH_DB="$HEALTH_DIR/metrics.db"
PID_FILE="$HEALTH_DIR/daemon.pid"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize health monitoring
init_health() {
    echo -e "${BLUE}[HEALTH]${NC} Initializing infrastructure health monitoring..."

    mkdir -p "$HEALTH_DIR"

    # Create database for health metrics
    sqlite3 "$HEALTH_DB" <<EOF
CREATE TABLE IF NOT EXISTS health_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    system TEXT NOT NULL,
    component TEXT NOT NULL,
    status TEXT NOT NULL,
    response_time REAL,
    message TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    system TEXT NOT NULL,
    component TEXT NOT NULL,
    severity TEXT NOT NULL,
    message TEXT NOT NULL,
    resolved BOOLEAN DEFAULT 0,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS uptime_stats (
    system TEXT PRIMARY KEY,
    total_checks INTEGER DEFAULT 0,
    successful_checks INTEGER DEFAULT 0,
    failed_checks INTEGER DEFAULT 0,
    last_check TEXT,
    last_status TEXT
);

CREATE INDEX IF NOT EXISTS idx_health_system ON health_checks(system);
CREATE INDEX IF NOT EXISTS idx_health_timestamp ON health_checks(timestamp);
CREATE INDEX IF NOT EXISTS idx_alerts_resolved ON alerts(resolved);
EOF

    echo -e "${GREEN}[HEALTH]${NC} Health monitoring initialized at: $HEALTH_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "health-monitor" "Initialized [HEALTH] infrastructure monitoring system" "coordination,health,monitoring" 2>/dev/null || true
    fi
}

# Log health check
log_check() {
    local system="$1"
    local component="$2"
    local status="$3"
    local response_time="${4:-0}"
    local message="${5:-}"

    sqlite3 "$HEALTH_DB" <<EOF
INSERT INTO health_checks (system, component, status, response_time, message)
VALUES ('${system}', '${component}', '${status}', ${response_time}, '${message}');

INSERT OR REPLACE INTO uptime_stats (system, total_checks, successful_checks, failed_checks, last_check, last_status)
VALUES (
    '${system}',
    COALESCE((SELECT total_checks FROM uptime_stats WHERE system='${system}'), 0) + 1,
    COALESCE((SELECT successful_checks FROM uptime_stats WHERE system='${system}'), 0) + CASE WHEN '${status}'='healthy' THEN 1 ELSE 0 END,
    COALESCE((SELECT failed_checks FROM uptime_stats WHERE system='${system}'), 0) + CASE WHEN '${status}'!='healthy' THEN 1 ELSE 0 END,
    datetime('now'),
    '${status}'
);
EOF
}

# Create alert
create_alert() {
    local system="$1"
    local component="$2"
    local severity="$3"
    local message="$4"

    sqlite3 "$HEALTH_DB" <<EOF
INSERT INTO alerts (system, component, severity, message)
VALUES ('${system}', '${component}', '${severity}', '${message}');
EOF

    echo -e "${RED}[ALERT]${NC} $severity: $system/$component - $message"

    # Log to memory for critical alerts
    if [ "$severity" = "critical" ] && [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log alert "health-monitor" "CRITICAL: $system/$component - $message" "health,alert,critical" 2>/dev/null || true
    fi
}

# Check GitHub Actions
check_github() {
    echo -e "${BLUE}[HEALTH]${NC} Checking GitHub Actions..."

    local start_time=$(date +%s.%N)

    # Check if gh is available
    if ! command -v gh &> /dev/null; then
        log_check "github" "cli" "unavailable" 0 "gh CLI not installed"
        return 1
    fi

    # Check authentication
    if ! gh auth status &>/dev/null; then
        log_check "github" "auth" "degraded" 0 "Not authenticated"
        create_alert "github" "auth" "warning" "GitHub CLI not authenticated"
        return 1
    fi

    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)

    log_check "github" "cli" "healthy" "$response_time" "GitHub CLI operational"
    echo -e "${GREEN}  ✓${NC} GitHub operational (${response_time}s)"
}

# Check Cloudflare
check_cloudflare() {
    echo -e "${BLUE}[HEALTH]${NC} Checking Cloudflare..."

    local start_time=$(date +%s.%N)

    # Check if wrangler is available
    if ! command -v wrangler &> /dev/null; then
        log_check "cloudflare" "wrangler" "unavailable" 0 "Wrangler not installed"
        return 1
    fi

    # Check authentication
    if ! wrangler whoami &>/dev/null; then
        log_check "cloudflare" "auth" "degraded" 0 "Not authenticated"
        create_alert "cloudflare" "auth" "warning" "Wrangler not authenticated"
        return 1
    fi

    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)

    log_check "cloudflare" "wrangler" "healthy" "$response_time" "Wrangler operational"
    echo -e "${GREEN}  ✓${NC} Cloudflare operational (${response_time}s)"
}

# Check Pi cluster
check_pi_cluster() {
    echo -e "${BLUE}[HEALTH]${NC} Checking Pi cluster..."

    local pi_hosts=("192.168.4.38:lucidia" "192.168.4.64:blackroad-pi" "192.168.4.99:lucidia-alt")

    for host_info in "${pi_hosts[@]}"; do
        local ip=$(echo "$host_info" | cut -d: -f1)
        local hostname=$(echo "$host_info" | cut -d: -f2)

        local start_time=$(date +%s.%N)

        # Check if host is reachable
        if timeout 2 nc -z "$ip" 22 2>/dev/null; then
            local end_time=$(date +%s.%N)
            local response_time=$(echo "$end_time - $start_time" | bc)

            log_check "pi-cluster" "$hostname" "healthy" "$response_time" "Host reachable"
            echo -e "${GREEN}  ✓${NC} $hostname ($ip) - healthy"
        else
            log_check "pi-cluster" "$hostname" "down" 2.0 "Host unreachable"
            create_alert "pi-cluster" "$hostname" "warning" "Host $ip unreachable"
            echo -e "${RED}  ✗${NC} $hostname ($ip) - down"
        fi
    done
}

# Check Railway
check_railway() {
    echo -e "${BLUE}[HEALTH]${NC} Checking Railway..."

    local start_time=$(date +%s.%N)

    # Check if railway CLI is available
    if ! command -v railway &> /dev/null; then
        log_check "railway" "cli" "unavailable" 0 "Railway CLI not installed"
        echo -e "${YELLOW}  ⚠${NC} Railway CLI not available"
        return 1
    fi

    local end_time=$(date +%s.%N)
    local response_time=$(echo "$end_time - $start_time" | bc)

    log_check "railway" "cli" "healthy" "$response_time" "Railway CLI available"
    echo -e "${GREEN}  ✓${NC} Railway CLI available"
}

# Run all health checks
check_all() {
    echo -e "${PURPLE}[HEALTH]${NC} Running full infrastructure health check..."
    echo ""

    check_github
    check_cloudflare
    check_pi_cluster
    check_railway

    echo ""
    echo -e "${GREEN}[HEALTH]${NC} Health check complete!"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "health-check" "Completed full infrastructure health check" "coordination,health,check" 2>/dev/null || true
    fi
}

# Show current status
show_status() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       💚 INFRASTRUCTURE HEALTH STATUS 💚              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Overall health
    echo -e "${BLUE}Overall Health by System:${NC}"
    sqlite3 -column -header "$HEALTH_DB" <<EOF
SELECT
    system,
    last_status as status,
    ROUND(100.0 * successful_checks / total_checks, 1) as uptime_pct,
    total_checks as checks,
    substr(last_check, 1, 16) as last_checked
FROM uptime_stats
ORDER BY system;
EOF

    echo ""
    echo -e "${BLUE}Recent Health Checks:${NC}"
    sqlite3 -column -header "$HEALTH_DB" <<EOF
SELECT
    system || '/' || component as target,
    status,
    ROUND(response_time, 3) as response_sec,
    substr(timestamp, 12, 8) as time
FROM health_checks
ORDER BY timestamp DESC
LIMIT 10;
EOF

    echo ""
    echo -e "${BLUE}Active Alerts:${NC}"
    local active_alerts=$(sqlite3 "$HEALTH_DB" "SELECT COUNT(*) FROM alerts WHERE resolved=0;")

    if [ "$active_alerts" -eq 0 ]; then
        echo -e "${GREEN}  No active alerts ✓${NC}"
    else
        sqlite3 -column -header "$HEALTH_DB" <<EOF
SELECT
    severity,
    system || '/' || component as target,
    message,
    substr(timestamp, 1, 16) as when
FROM alerts
WHERE resolved = 0
ORDER BY timestamp DESC;
EOF
    fi
}

# Show alerts
show_alerts() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               🚨 SYSTEM ALERTS 🚨                      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_alerts=$(sqlite3 "$HEALTH_DB" "SELECT COUNT(*) FROM alerts;")
    local active_alerts=$(sqlite3 "$HEALTH_DB" "SELECT COUNT(*) FROM alerts WHERE resolved=0;")

    echo -e "${GREEN}Total Alerts:${NC}  $total_alerts"
    echo -e "${YELLOW}Active:${NC}        $active_alerts"
    echo ""

    if [ "$active_alerts" -gt 0 ]; then
        echo -e "${RED}Active Alerts:${NC}"
        sqlite3 -column -header "$HEALTH_DB" <<EOF
SELECT
    severity,
    system,
    component,
    message,
    substr(timestamp, 1, 16) as when
FROM alerts
WHERE resolved = 0
ORDER BY
    CASE severity
        WHEN 'critical' THEN 1
        WHEN 'warning' THEN 2
        ELSE 3
    END,
    timestamp DESC;
EOF
    else
        echo -e "${GREEN}✓ No active alerts!${NC}"
    fi
}

# Daemon mode
run_daemon() {
    echo -e "${BLUE}[HEALTH]${NC} Starting health monitor daemon..."

    # Check if already running
    if [ -f "$PID_FILE" ]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}[HEALTH]${NC} Daemon already running (PID: $old_pid)"
            return 0
        fi
    fi

    # Save PID
    echo $$ > "$PID_FILE"

    echo -e "${GREEN}[HEALTH]${NC} Daemon started (PID: $$)"
    echo -e "${CYAN}[HEALTH]${NC} Checking infrastructure every 5 minutes..."

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log started "health-daemon" "Health monitoring daemon started (PID: $$)" "coordination,health,daemon" 2>/dev/null || true
    fi

    # Main daemon loop
    while true; do
        check_all &>/dev/null

        # Sleep for 5 minutes
        sleep 300
    done
}

# Stop daemon
stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}[HEALTH]${NC} Daemon not running"
        return 0
    fi

    local pid=$(cat "$PID_FILE")

    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid"
        rm "$PID_FILE"
        echo -e "${GREEN}[HEALTH]${NC} Daemon stopped (PID: $pid)"

        # Log to memory
        if [ -f ~/memory-system.sh ]; then
            ~/memory-system.sh log stopped "health-daemon" "Health monitoring daemon stopped" "coordination,health,daemon" 2>/dev/null || true
        fi
    else
        rm "$PID_FILE"
        echo -e "${YELLOW}[HEALTH]${NC} Daemon was not running"
    fi
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Infrastructure Health Monitor [HEALTH]${NC}

USAGE:
    blackroad-health-monitor.sh <command> [options]

COMMANDS:
    init                Initialize health monitoring
    check               Run full health check
    status              Show current health status
    alerts              Show active alerts
    daemon              Start health monitor daemon
    stop                Stop daemon
    github              Check GitHub only
    cloudflare          Check Cloudflare only
    pi                  Check Pi cluster only
    railway             Check Railway only
    help                Show this help

EXAMPLES:
    # Initialize
    blackroad-health-monitor.sh init

    # Run health check
    blackroad-health-monitor.sh check

    # Show status
    blackroad-health-monitor.sh status

    # Show alerts
    blackroad-health-monitor.sh alerts

    # Start daemon (runs checks every 5 minutes)
    blackroad-health-monitor.sh daemon &

    # Stop daemon
    blackroad-health-monitor.sh stop

    # Check specific system
    blackroad-health-monitor.sh github
    blackroad-health-monitor.sh cloudflare

DATABASE: $HEALTH_DB
PID FILE: $PID_FILE
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_health
            ;;
        check)
            check_all
            ;;
        status)
            show_status
            ;;
        alerts)
            show_alerts
            ;;
        daemon)
            run_daemon
            ;;
        stop)
            stop_daemon
            ;;
        github)
            check_github
            ;;
        cloudflare)
            check_cloudflare
            ;;
        pi)
            check_pi_cluster
            ;;
        railway)
            check_railway
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[HEALTH]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
