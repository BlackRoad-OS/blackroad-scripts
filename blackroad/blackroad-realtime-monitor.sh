#!/bin/bash
# BlackRoad Real-Time Monitoring Dashboard
# Continuous monitoring of all infrastructure components

MONITOR_VERSION="1.0.0"
STATE_DIR="$HOME/.blackroad/monitor"
STATE_FILE="$STATE_DIR/state.json"
HISTORY_FILE="$STATE_DIR/history.jsonl"

mkdir -p "$STATE_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Get current state of all infrastructure
check_github() {
    local status="unknown"
    local details=""

    if gh auth status &>/dev/null; then
        status="healthy"
        local orgs=$(gh api orgs -q '.[] | select(.login | startswith("BlackRoad")) | .login' 2>/dev/null | wc -l | tr -d ' ')
        local repos=$(gh repo list BlackRoad-OS --limit 1000 --json name 2>/dev/null | jq -r '. | length' 2>/dev/null || echo "0")
        details="$orgs orgs, $repos repos"
    else
        status="error"
        details="Authentication failed"
    fi

    jq -n \
        --arg status "$status" \
        --arg details "$details" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status: $status, details: $details, timestamp: $timestamp}'
}

check_cloudflare() {
    local status="unknown"
    local details=""

    if wrangler whoami &>/dev/null; then
        status="healthy"
        local account=$(wrangler whoami 2>/dev/null | grep "Account ID" | awk '{print $NF}' || echo "unknown")
        details="Connected (${account:0:8}...)"
    else
        status="error"
        details="Not authenticated"
    fi

    jq -n \
        --arg status "$status" \
        --arg details "$details" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status: $status, details: $details, timestamp: $timestamp}'
}

check_pi_device() {
    local ip="$1"
    local name="$2"
    local status="unknown"
    local details=""

    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        status="healthy"
        details="Responding to ping"
    else
        status="error"
        details="Unreachable"
    fi

    jq -n \
        --arg name "$name" \
        --arg ip "$ip" \
        --arg status "$status" \
        --arg details "$details" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{name: $name, ip: $ip, status: $status, details: $details, timestamp: $timestamp}'
}

check_port_service() {
    local ip="$1"
    local port="$2"
    local name="$3"
    local status="unknown"
    local details=""

    if nc -z -w 2 "$ip" "$port" &>/dev/null; then
        status="healthy"
        details="Port $port open"
    else
        status="error"
        details="Port $port closed"
    fi

    jq -n \
        --arg name "$name" \
        --arg endpoint "$ip:$port" \
        --arg status "$status" \
        --arg details "$details" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{name: $name, endpoint: $endpoint, status: $status, details: $details, timestamp: $timestamp}'
}

check_memory_system() {
    local status="unknown"
    local details=""

    if [ -f "$HOME/memory-system.sh" ] && [ -d "$HOME/.blackroad/memory" ]; then
        status="healthy"
        local entries=$(~/memory-system.sh summary 2>/dev/null | grep "Total entries" | awk '{print $NF}' || echo "0")
        details="$entries entries"
    else
        status="warning"
        details="Not initialized"
    fi

    jq -n \
        --arg status "$status" \
        --arg details "$details" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status: $status, details: $details, timestamp: $timestamp}'
}

# Collect all infrastructure state
collect_state() {
    local github_state=$(check_github)
    local cloudflare_state=$(check_cloudflare)
    local memory_state=$(check_memory_system)

    # Pi devices
    local pi_lucidia=$(check_pi_device "192.168.4.38" "lucidia")
    local pi_blackroad=$(check_pi_device "192.168.4.64" "blackroad-pi")
    local pi_alt=$(check_pi_device "192.168.4.99" "lucidia-alt")

    # Port services
    local port_iphone=$(check_port_service "192.168.4.68" "8080" "iphone-koder")
    local port_local=$(check_port_service "127.0.0.1" "8080" "local-8080")

    # Combine into full state
    jq -n \
        --argjson github "$github_state" \
        --argjson cloudflare "$cloudflare_state" \
        --argjson memory "$memory_state" \
        --argjson pi_lucidia "$pi_lucidia" \
        --argjson pi_blackroad "$pi_blackroad" \
        --argjson pi_alt "$pi_alt" \
        --argjson port_iphone "$port_iphone" \
        --argjson port_local "$port_local" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            timestamp: $timestamp,
            github: $github,
            cloudflare: $cloudflare,
            memory: $memory,
            pi_devices: {
                lucidia: $pi_lucidia,
                blackroad_pi: $pi_blackroad,
                lucidia_alt: $pi_alt
            },
            services: {
                iphone_koder: $port_iphone,
                local_8080: $port_local
            }
        }'
}

# Display dashboard
display_dashboard() {
    local state="$1"

    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  BlackRoad Real-Time Infrastructure Monitor v$MONITOR_VERSION         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local timestamp=$(echo "$state" | jq -r '.timestamp')
    echo -e "${BLUE}Last updated: $timestamp${NC}"
    echo ""

    # GitHub
    local gh_status=$(echo "$state" | jq -r '.github.status')
    local gh_details=$(echo "$state" | jq -r '.github.details')
    local gh_icon=$([ "$gh_status" = "healthy" ] && echo "${GREEN}✅" || echo "${RED}❌")
    echo -e "${gh_icon} GitHub: $gh_status${NC} - $gh_details"

    # Cloudflare
    local cf_status=$(echo "$state" | jq -r '.cloudflare.status')
    local cf_details=$(echo "$state" | jq -r '.cloudflare.details')
    local cf_icon=$([ "$cf_status" = "healthy" ] && echo "${GREEN}✅" || echo "${RED}❌")
    echo -e "${cf_icon} Cloudflare: $cf_status${NC} - $cf_details"

    # Memory System
    local mem_status=$(echo "$state" | jq -r '.memory.status')
    local mem_details=$(echo "$state" | jq -r '.memory.details')
    local mem_icon=$([ "$mem_status" = "healthy" ] && echo "${GREEN}✅" || ([ "$mem_status" = "warning" ] && echo "${YELLOW}⚠️ " || echo "${RED}❌"))
    echo -e "${mem_icon} Memory System: $mem_status${NC} - $mem_details"

    echo ""
    echo -e "${MAGENTA}🥧 Raspberry Pi Devices:${NC}"

    # Pi devices
    for pi in lucidia blackroad_pi lucidia_alt; do
        local pi_name=$(echo "$state" | jq -r ".pi_devices.$pi.name")
        local pi_ip=$(echo "$state" | jq -r ".pi_devices.$pi.ip")
        local pi_status=$(echo "$state" | jq -r ".pi_devices.$pi.status")
        local pi_details=$(echo "$state" | jq -r ".pi_devices.$pi.details")
        local pi_icon=$([ "$pi_status" = "healthy" ] && echo "${GREEN}✅" || echo "${RED}❌")
        echo -e "  ${pi_icon} $pi_name ($pi_ip): $pi_status${NC} - $pi_details"
    done

    echo ""
    echo -e "${BLUE}🌐 Port 8080 Services:${NC}"

    # Services
    for svc in iphone_koder local_8080; do
        local svc_name=$(echo "$state" | jq -r ".services.$svc.name")
        local svc_endpoint=$(echo "$state" | jq -r ".services.$svc.endpoint")
        local svc_status=$(echo "$state" | jq -r ".services.$svc.status")
        local svc_details=$(echo "$state" | jq -r ".services.$svc.details")
        local svc_icon=$([ "$svc_status" = "healthy" ] && echo "${GREEN}✅" || echo "${RED}❌")
        echo -e "  ${svc_icon} $svc_name ($svc_endpoint): $svc_status${NC} - $svc_details"
    done

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"
}

# Save state to history
save_state() {
    local state="$1"

    # Save current state
    echo "$state" > "$STATE_FILE"

    # Append to history
    echo "$state" >> "$HISTORY_FILE"
}

# Main monitoring loop
monitor() {
    local interval="${1:-30}"  # Default 30 seconds

    while true; do
        local state=$(collect_state)
        save_state "$state"
        display_dashboard "$state"
        sleep "$interval"
    done
}

# Export state for external use
export_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "{\"error\": \"No state file found\"}"
    fi
}

# Check specific component
check_component() {
    local component="$1"

    case "$component" in
        github)
            check_github
            ;;
        cloudflare)
            check_cloudflare
            ;;
        memory)
            check_memory_system
            ;;
        pi-*)
            local name="${component#pi-}"
            local ip=""
            case "$name" in
                lucidia) ip="192.168.4.38" ;;
                blackroad) ip="192.168.4.64" ;;
                alt) ip="192.168.4.99" ;;
            esac
            if [ -n "$ip" ]; then
                check_pi_device "$ip" "$name"
            fi
            ;;
        *)
            echo "{\"error\": \"Unknown component: $component\"}"
            ;;
    esac
}

# CLI
case "${1:-monitor}" in
    monitor)
        monitor "${2:-30}"
        ;;
    once)
        state=$(collect_state)
        save_state "$state"
        display_dashboard "$state"
        ;;
    export)
        export_state
        ;;
    check)
        check_component "$2"
        ;;
    history)
        tail -n "${2:-10}" "$HISTORY_FILE" 2>/dev/null || echo "[]"
        ;;
    *)
        echo "Usage: $0 {monitor [interval]|once|export|check <component>|history [lines]}"
        exit 1
        ;;
esac
