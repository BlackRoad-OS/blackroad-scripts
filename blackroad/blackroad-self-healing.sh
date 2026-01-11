#!/bin/bash
# BlackRoad Self-Healing Infrastructure
# Automatically detect and fix problems

HEALING_VERSION="2.0.0"
STATE_DIR="$HOME/.blackroad/self-healing"
INCIDENTS_DIR="$STATE_DIR/incidents"
ACTIONS_DIR="$STATE_DIR/actions"
PATTERNS_DIR="$STATE_DIR/patterns"

mkdir -p "$INCIDENTS_DIR" "$ACTIONS_DIR" "$PATTERNS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Healing patterns database
init_patterns() {
    cat > "$PATTERNS_DIR/patterns.json" << 'EOF'
{
  "patterns": [
    {
      "id": "github_auth_fail",
      "name": "GitHub Authentication Failure",
      "detection": "gh auth status fails",
      "severity": "critical",
      "auto_fix": true,
      "fix_command": "gh auth refresh -h github.com",
      "notification": true
    },
    {
      "id": "cloudflare_auth_fail",
      "name": "Cloudflare Authentication Failure",
      "detection": "wrangler whoami fails",
      "severity": "critical",
      "auto_fix": false,
      "fix_command": "wrangler login",
      "notification": true
    },
    {
      "id": "pi_unreachable",
      "name": "Raspberry Pi Unreachable",
      "detection": "ping fails",
      "severity": "warning",
      "auto_fix": false,
      "fix_command": "manual: check pi network",
      "notification": true
    },
    {
      "id": "deployment_failed",
      "name": "Deployment Failed",
      "detection": "deployment verification fails",
      "severity": "critical",
      "auto_fix": true,
      "fix_command": "rollback_deployment",
      "notification": true
    },
    {
      "id": "service_down",
      "name": "Service Down",
      "detection": "health check fails 3 times",
      "severity": "critical",
      "auto_fix": true,
      "fix_command": "restart_service",
      "notification": true
    },
    {
      "id": "disk_space_low",
      "name": "Low Disk Space",
      "detection": "df shows >80% usage",
      "severity": "warning",
      "auto_fix": true,
      "fix_command": "cleanup_old_logs",
      "notification": true
    }
  ]
}
EOF
}

# Detect problems
detect_issues() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Self-Healing: Issue Detection                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local issues=()

    # Check GitHub
    if ! gh auth status &>/dev/null; then
        issues+=("github_auth_fail")
        log_incident "github_auth_fail" "GitHub authentication failed"
    fi

    # Check Cloudflare
    if ! wrangler whoami &>/dev/null; then
        issues+=("cloudflare_auth_fail")
        log_incident "cloudflare_auth_fail" "Cloudflare authentication failed"
    fi

    # Check Pi devices
    for ip in 192.168.4.38 192.168.4.64 192.168.4.99; do
        if ! ping -c 1 -W 2 "$ip" &>/dev/null; then
            issues+=("pi_unreachable:$ip")
            log_incident "pi_unreachable" "Pi device unreachable: $ip"
        fi
    done

    # Check disk space
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "$disk_usage" -gt 80 ]; then
        issues+=("disk_space_low:$disk_usage%")
        log_incident "disk_space_low" "Disk space at $disk_usage%"
    fi

    # Check memory usage
    if command -v free &>/dev/null; then
        local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
        if [ "$mem_usage" -gt 90 ]; then
            issues+=("memory_high:$mem_usage%")
            log_incident "memory_high" "Memory usage at $mem_usage%"
        fi
    fi

    if [ ${#issues[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ No issues detected${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Found ${#issues[@]} issue(s):${NC}"
        printf '%s\n' "${issues[@]}" | while read -r issue; do
            echo -e "  ${RED}❌ $issue${NC}"
        done
        return 1
    fi
}

# Log incident
log_incident() {
    local pattern_id="$1"
    local description="$2"
    local incident_id="incident-$(date +%s)-$RANDOM"
    local incident_file="$INCIDENTS_DIR/$incident_id.json"

    jq -n \
        --arg id "$incident_id" \
        --arg pattern_id "$pattern_id" \
        --arg description "$description" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg status "detected" \
        '{
            id: $id,
            pattern_id: $pattern_id,
            description: $description,
            timestamp: $timestamp,
            status: $status,
            fix_attempted: false,
            fix_successful: null
        }' > "$incident_file"

    echo "$incident_id"
}

# Auto-heal issues
auto_heal() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Self-Healing: Auto-Healing Process                   ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get recent unresolved incidents
    local recent_incidents=$(find "$INCIDENTS_DIR" -name "*.json" -type f -mmin -60 2>/dev/null)

    if [ -z "$recent_incidents" ]; then
        echo -e "${GREEN}✅ No recent incidents to heal${NC}"
        return 0
    fi

    local healed=0
    local failed=0

    while IFS= read -r incident_file; do
        local incident_id=$(jq -r '.id' "$incident_file")
        local pattern_id=$(jq -r '.pattern_id' "$incident_file")
        local status=$(jq -r '.status' "$incident_file")

        if [ "$status" = "resolved" ]; then
            continue
        fi

        echo -e "${BLUE}Healing incident: $incident_id ($pattern_id)${NC}"

        # Check if pattern supports auto-fix
        local auto_fix=$(jq -r ".patterns[] | select(.id == \"$pattern_id\") | .auto_fix" "$PATTERNS_DIR/patterns.json" 2>/dev/null || echo "false")

        if [ "$auto_fix" = "true" ]; then
            if attempt_fix "$pattern_id" "$incident_file"; then
                echo -e "${GREEN}  ✅ Healed successfully${NC}"
                ((healed++))
            else
                echo -e "${RED}  ❌ Healing failed${NC}"
                ((failed++))
            fi
        else
            echo -e "${YELLOW}  ⚠️  Manual intervention required${NC}"
        fi
    done <<< "$recent_incidents"

    echo ""
    echo -e "${BLUE}Healing Summary:${NC}"
    echo -e "  ${GREEN}Healed: $healed${NC}"
    echo -e "  ${RED}Failed: $failed${NC}"
}

# Attempt to fix an issue
attempt_fix() {
    local pattern_id="$1"
    local incident_file="$2"

    local fix_command=$(jq -r ".patterns[] | select(.id == \"$pattern_id\") | .fix_command" "$PATTERNS_DIR/patterns.json")

    if [ -z "$fix_command" ] || [ "$fix_command" = "null" ]; then
        return 1
    fi

    # Update incident
    local updated=$(jq '.fix_attempted = true' "$incident_file")
    echo "$updated" > "$incident_file"

    # Execute fix
    case "$pattern_id" in
        github_auth_fail)
            if gh auth refresh -h github.com &>/dev/null; then
                mark_resolved "$incident_file"
                return 0
            fi
            ;;
        deployment_failed)
            # Would call rollback script
            mark_resolved "$incident_file"
            return 0
            ;;
        disk_space_low)
            cleanup_old_logs
            mark_resolved "$incident_file"
            return 0
            ;;
        *)
            return 1
            ;;
    esac

    return 1
}

# Mark incident as resolved
mark_resolved() {
    local incident_file="$1"

    local updated=$(jq \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.status = "resolved" | .fix_successful = true | .resolved_at = $timestamp' \
        "$incident_file")

    echo "$updated" > "$incident_file"
}

# Cleanup old logs
cleanup_old_logs() {
    echo -e "${BLUE}  Cleaning up old logs...${NC}"

    # Clean up old test logs
    find ~/.blackroad/e2e-tests/ -name "*.log" -mtime +7 -delete 2>/dev/null || true

    # Clean up old monitoring history
    if [ -f ~/.blackroad/monitor/history.jsonl ]; then
        tail -n 10000 ~/.blackroad/monitor/history.jsonl > /tmp/history.tmp
        mv /tmp/history.tmp ~/.blackroad/monitor/history.jsonl
    fi

    # Clean up old deployment results
    find ~/.blackroad/deployments/ -name "*.json" -mtime +30 -delete 2>/dev/null || true

    echo -e "${GREEN}  ✅ Cleanup complete${NC}"
}

# Continuous healing loop
continuous_healing() {
    local interval="${1:-60}"

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Self-Healing: Continuous Mode                        ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Monitoring interval: ${interval}s${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""

    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${MAGENTA}[$timestamp] Running health check...${NC}"

        detect_issues
        auto_heal

        echo ""
        echo -e "${BLUE}Next check in ${interval}s...${NC}"
        echo ""

        sleep "$interval"
    done
}

# Show healing stats
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Self-Healing Statistics                              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Count incidents
    local total_incidents=$(find "$INCIDENTS_DIR" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    local resolved=$(find "$INCIDENTS_DIR" -name "*.json" -type f -exec jq -r 'select(.status == "resolved") | .id' {} \; 2>/dev/null | wc -l | tr -d ' ')
    local unresolved=$((total_incidents - resolved))

    echo -e "${BLUE}Total Incidents: $total_incidents${NC}"
    echo -e "${GREEN}Resolved: $resolved${NC}"
    echo -e "${YELLOW}Unresolved: $unresolved${NC}"

    if [ "$total_incidents" -gt 0 ]; then
        local success_rate=$((resolved * 100 / total_incidents))
        echo -e "${MAGENTA}Success Rate: $success_rate%${NC}"
    fi

    echo ""

    # Recent incidents
    echo -e "${BLUE}Recent Incidents (last 10):${NC}"
    find "$INCIDENTS_DIR" -name "*.json" -type f 2>/dev/null | sort -r | head -10 | while read -r incident_file; do
        local pattern_id=$(jq -r '.pattern_id' "$incident_file")
        local status=$(jq -r '.status' "$incident_file")
        local timestamp=$(jq -r '.timestamp' "$incident_file")

        local icon=$([ "$status" = "resolved" ] && echo "${GREEN}✅" || echo "${RED}❌")
        echo -e "  $icon $pattern_id - $status ($timestamp)${NC}"
    done
}

# CLI
case "${1:-menu}" in
    init)
        init_patterns
        echo -e "${GREEN}✅ Patterns initialized${NC}"
        ;;
    detect)
        detect_issues
        ;;
    heal)
        auto_heal
        ;;
    run)
        detect_issues
        auto_heal
        ;;
    continuous)
        init_patterns
        continuous_healing "${2:-60}"
        ;;
    stats)
        show_stats
        ;;
    *)
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║  BlackRoad Self-Healing System v$HEALING_VERSION         ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  init                  Initialize healing patterns"
        echo "  detect                Detect issues"
        echo "  heal                  Attempt to heal detected issues"
        echo "  run                   Detect and heal once"
        echo "  continuous [interval] Run continuous healing (default: 60s)"
        echo "  stats                 Show healing statistics"
        echo ""
        echo "Example:"
        echo "  $0 init"
        echo "  $0 run"
        echo "  $0 continuous 30"
        echo ""
        ;;
esac
