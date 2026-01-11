#!/bin/bash
# BlackRoad Automated Health Checks
# Continuous health monitoring with alerting

HEALTH_VERSION="1.0.0"
STATE_DIR="$HOME/.blackroad/health"
CHECKS_DIR="$STATE_DIR/checks"
ALERTS_DIR="$STATE_DIR/alerts"
CONFIG_FILE="$STATE_DIR/config.json"

mkdir -p "$CHECKS_DIR" "$ALERTS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize config
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "checks": {
    "github": {
      "enabled": true,
      "interval": 60,
      "critical": true
    },
    "cloudflare": {
      "enabled": true,
      "interval": 60,
      "critical": true
    },
    "pi_devices": {
      "enabled": true,
      "interval": 30,
      "critical": false
    },
    "memory_system": {
      "enabled": true,
      "interval": 300,
      "critical": false
    }
  },
  "alerting": {
    "enabled": true,
    "email": "blackroad.systems@gmail.com",
    "slack_webhook": "",
    "discord_webhook": ""
  },
  "deployment_pipeline": {
    "git_to_cloudflare": {
      "enabled": true,
      "verify_after_push": true,
      "auto_rollback": false
    },
    "git_to_pi": {
      "enabled": true,
      "verify_deployment": true,
      "health_check_retries": 3
    }
  }
}
EOF
        echo -e "${GREEN}✅ Config initialized at $CONFIG_FILE${NC}"
    fi
}

# Health check: GitHub
check_github_health() {
    local result_file="$CHECKS_DIR/github-$(date +%s).json"
    local status="pass"
    local message="GitHub API healthy"

    if ! gh auth status &>/dev/null; then
        status="fail"
        message="GitHub authentication failed"
    elif ! gh api rate_limit &>/dev/null; then
        status="fail"
        message="GitHub API unreachable"
    fi

    jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg component "github" \
        '{component: $component, status: $status, message: $message, timestamp: $timestamp}' \
        > "$result_file"

    echo "$result_file"
}

# Health check: Cloudflare
check_cloudflare_health() {
    local result_file="$CHECKS_DIR/cloudflare-$(date +%s).json"
    local status="pass"
    local message="Cloudflare authenticated"

    if ! wrangler whoami &>/dev/null; then
        status="fail"
        message="Cloudflare authentication failed"
    fi

    jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg component "cloudflare" \
        '{component: $component, status: $status, message: $message, timestamp: $timestamp}' \
        > "$result_file"

    echo "$result_file"
}

# Health check: Pi devices
check_pi_health() {
    local result_file="$CHECKS_DIR/pi-devices-$(date +%s).json"
    local total=3
    local healthy=0

    for ip in 192.168.4.38 192.168.4.64 192.168.4.99; do
        if ping -c 1 -W 2 "$ip" &>/dev/null; then
            ((healthy++))
        fi
    done

    local status="pass"
    local message="$healthy/$total Pi devices responding"

    if [ $healthy -eq 0 ]; then
        status="fail"
        message="All Pi devices unreachable"
    elif [ $healthy -lt $total ]; then
        status="warning"
    fi

    jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --argjson healthy "$healthy" \
        --argjson total "$total" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg component "pi_devices" \
        '{component: $component, status: $status, message: $message, healthy: $healthy, total: $total, timestamp: $timestamp}' \
        > "$result_file"

    echo "$result_file"
}

# Health check: Memory system
check_memory_health() {
    local result_file="$CHECKS_DIR/memory-$(date +%s).json"
    local status="pass"
    local message="Memory system operational"

    if [ ! -f "$HOME/memory-system.sh" ]; then
        status="fail"
        message="Memory system not found"
    elif [ ! -d "$HOME/.blackroad/memory" ]; then
        status="fail"
        message="Memory directory missing"
    fi

    jq -n \
        --arg status "$status" \
        --arg message "$message" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg component "memory_system" \
        '{component: $component, status: $status, message: $message, timestamp: $timestamp}' \
        > "$result_file"

    echo "$result_file"
}

# Send alert
send_alert() {
    local component="$1"
    local status="$2"
    local message="$3"
    local alert_file="$ALERTS_DIR/alert-$(date +%s).json"

    local alert_data=$(jq -n \
        --arg component "$component" \
        --arg status "$status" \
        --arg message "$message" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{component: $component, status: $status, message: $message, timestamp: $timestamp}')

    echo "$alert_data" > "$alert_file"

    echo -e "${RED}🚨 ALERT: [$component] $status - $message${NC}"

    # Log to memory system if available
    if [ -f "$HOME/memory-system.sh" ]; then
        ~/memory-system.sh log alert "$component" "$message" 2>/dev/null || true
    fi
}

# Run all health checks
run_all_checks() {
    echo -e "${BLUE}Running health checks...${NC}"

    local github_result=$(check_github_health)
    local cloudflare_result=$(check_cloudflare_health)
    local pi_result=$(check_pi_health)
    local memory_result=$(check_memory_health)

    # Process results and send alerts if needed
    for result_file in "$github_result" "$cloudflare_result" "$pi_result" "$memory_result"; do
        local status=$(jq -r '.status' "$result_file")
        local component=$(jq -r '.component' "$result_file")
        local message=$(jq -r '.message' "$result_file")

        if [ "$status" = "fail" ]; then
            send_alert "$component" "$status" "$message"
        elif [ "$status" = "warning" ]; then
            echo -e "${YELLOW}⚠️  WARNING: [$component] $message${NC}"
        else
            echo -e "${GREEN}✅ [$component] $message${NC}"
        fi
    done

    echo -e "${BLUE}Health checks complete.${NC}"
}

# Deployment verification: Git to Cloudflare
verify_git_to_cloudflare() {
    local repo="$1"
    local expected_sha="$2"

    echo -e "${BLUE}Verifying deployment: $repo${NC}"

    # Check if repo exists on GitHub
    if ! gh repo view "$repo" &>/dev/null; then
        echo -e "${RED}❌ Repository not found: $repo${NC}"
        return 1
    fi

    # Check latest commit
    local actual_sha=$(gh api "repos/$repo/commits/main" -q '.sha' 2>/dev/null | head -c 7)

    if [ -n "$expected_sha" ] && [ "$actual_sha" != "${expected_sha:0:7}" ]; then
        echo -e "${YELLOW}⚠️  SHA mismatch: expected ${expected_sha:0:7}, got $actual_sha${NC}"
    else
        echo -e "${GREEN}✅ Latest commit: $actual_sha${NC}"
    fi

    # TODO: Verify Cloudflare Pages deployment
    echo -e "${BLUE}ℹ️  Cloudflare deployment verification not yet implemented${NC}"

    return 0
}

# Deployment verification: Git to Pi
verify_git_to_pi() {
    local pi_ip="$1"
    local service="$2"

    echo -e "${BLUE}Verifying Pi deployment: $service on $pi_ip${NC}"

    # Check Pi is reachable
    if ! ping -c 1 -W 2 "$pi_ip" &>/dev/null; then
        echo -e "${RED}❌ Pi unreachable: $pi_ip${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ Pi is reachable${NC}"

    # TODO: SSH check for service status
    echo -e "${BLUE}ℹ️  Service verification not yet implemented${NC}"

    return 0
}

# Monitor mode
monitor_health() {
    local interval="${1:-60}"

    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  BlackRoad Health Monitoring v$HEALTH_VERSION         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Monitoring interval: ${interval}s${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    while true; do
        run_all_checks
        echo ""
        echo -e "${BLUE}Next check in ${interval}s...${NC}"
        sleep "$interval"
    done
}

# CLI
case "${1:-check}" in
    init)
        init_config
        ;;
    check)
        init_config
        run_all_checks
        ;;
    monitor)
        init_config
        monitor_health "${2:-60}"
        ;;
    verify-cloudflare)
        verify_git_to_cloudflare "$2" "$3"
        ;;
    verify-pi)
        verify_git_to_pi "$2" "$3"
        ;;
    alerts)
        ls -lt "$ALERTS_DIR" | head -n "${2:-10}"
        ;;
    *)
        echo "BlackRoad Health Checks v$HEALTH_VERSION"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  init                           Initialize health check config"
        echo "  check                          Run all health checks once"
        echo "  monitor [interval]             Continuous monitoring (default: 60s)"
        echo "  verify-cloudflare <repo> [sha] Verify Git to Cloudflare deployment"
        echo "  verify-pi <ip> <service>       Verify Git to Pi deployment"
        echo "  alerts [count]                 Show recent alerts (default: 10)"
        echo ""
        exit 1
        ;;
esac
