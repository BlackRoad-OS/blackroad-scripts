#!/usr/bin/env bash
# BlackRoad End-to-End Test Suite
# Comprehensive testing for all devices and repositories
# Version: 1.0.0

set -euo pipefail

VERSION="1.0.0"
TEST_DIR="$HOME/.blackroad/tests"
RESULTS_DIR="$TEST_DIR/results/$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$RESULTS_DIR/test.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Initialize
init_tests() {
    mkdir -p "$RESULTS_DIR"
    touch "$LOG_FILE"

    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║  🖤🛣️  BlackRoad End-to-End Test Suite v1.0.0        ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    log "INFO" "Test suite started at $(date)"
    log "INFO" "Results directory: $RESULTS_DIR"
}

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%H:%M:%S')

    echo "[$timestamp] [$level] $msg" | tee -a "$LOG_FILE"
}

test_start() {
    local test_name="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "  [$TOTAL_TESTS] $test_name ... "
    log "TEST" "Starting: $test_name"
}

test_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}✓ PASS${NC}"
    log "PASS" "$1"
}

test_fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}✗ FAIL${NC}"
    log "FAIL" "$1"
}

test_skip() {
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    echo -e "${YELLOW}⊘ SKIP${NC}"
    log "SKIP" "$1"
}

# ============================================================
# DEVICE TESTS
# ============================================================

test_device_connectivity() {
    echo ""
    echo -e "${CYAN}━━━ Device Connectivity Tests ━━━${NC}"

    local devices=("lucidia-pi" "alice-pi" "aria-pi" "octavia-pi" "operator-shellfish")

    for device in "${devices[@]}"; do
        test_start "SSH connectivity: $device"

        if timeout 5 ssh -o ConnectTimeout=3 -o BatchMode=yes "$device" "echo OK" &>/dev/null; then
            test_pass "SSH connection to $device successful"
        else
            test_fail "SSH connection to $device failed"
        fi
    done
}

test_device_requirements() {
    echo ""
    echo -e "${CYAN}━━━ Device Requirements Tests ━━━${NC}"

    local devices=("lucidia-pi" "alice-pi" "aria-pi" "octavia-pi")

    for device in "${devices[@]}"; do
        # Test Git
        test_start "Git installed on $device"
        if ssh "$device" "command -v git &>/dev/null"; then
            test_pass "Git found on $device"
        else
            test_fail "Git not found on $device"
        fi

        # Test jq
        test_start "jq installed on $device"
        if ssh "$device" "command -v jq &>/dev/null"; then
            test_pass "jq found on $device"
        else
            test_fail "jq not found on $device (install with: sudo apt install jq)"
        fi

        # Test disk space
        test_start "Disk space on $device"
        local usage=$(ssh "$device" "df / | tail -1 | awk '{print \$5}' | tr -d '%'")
        if [[ $usage -lt 90 ]]; then
            test_pass "Disk usage on $device: ${usage}%"
        else
            test_fail "Disk usage on $device too high: ${usage}%"
        fi
    done
}

test_webhook_receivers() {
    echo ""
    echo -e "${CYAN}━━━ Webhook Receiver Tests ━━━${NC}"

    local -A ports=(
        ["lucidia-pi"]="9001"
        ["alice-pi"]="9002"
        ["aria-pi"]="9003"
        ["octavia-pi"]="9004"
    )

    for device in "${!ports[@]}"; do
        local port="${ports[$device]}"

        # Test systemd service
        test_start "Webhook service on $device"
        if ssh "$device" "systemctl is-active blackroad-webhook &>/dev/null"; then
            test_pass "Webhook service running on $device"
        else
            test_fail "Webhook service not running on $device"
        fi

        # Test health endpoint
        test_start "Health endpoint on $device:$port"
        local health_response=$(ssh "$device" "curl -s http://localhost:$port/health" 2>/dev/null || echo "")

        if echo "$health_response" | grep -q "healthy"; then
            test_pass "Health endpoint responding on $device:$port"
        else
            test_fail "Health endpoint not responding on $device:$port"
        fi
    done
}

# ============================================================
# REPOSITORY TESTS
# ============================================================

test_github_access() {
    echo ""
    echo -e "${CYAN}━━━ GitHub Access Tests ━━━${NC}"

    test_start "gh CLI authentication"
    if gh auth status &>/dev/null; then
        test_pass "gh CLI authenticated"
    else
        test_fail "gh CLI not authenticated (run: gh auth login)"
    fi

    test_start "List BlackRoad-OS repositories"
    local repo_count=$(gh repo list BlackRoad-OS --limit 100 --json name -q '. | length' 2>/dev/null || echo "0")

    if [[ $repo_count -gt 0 ]]; then
        test_pass "Found $repo_count repositories in BlackRoad-OS"
        echo "$repo_count" > "$RESULTS_DIR/repo_count.txt"
    else
        test_fail "Could not list BlackRoad-OS repositories"
    fi
}

test_clone_repositories() {
    echo ""
    echo -e "${CYAN}━━━ Repository Clone Tests ━━━${NC}"

    # Test repos (small ones for quick testing)
    local test_repos=(
        "BlackRoad-OS/blackroad-os-dashboard"
        "BlackRoad-OS/blackroad-os-deploy"
    )

    for repo in "${test_repos[@]}"; do
        test_start "Clone $repo to lucidia-pi"

        local repo_name=$(basename "$repo")
        local clone_cmd="cd /tmp && rm -rf $repo_name && git clone https://github.com/$repo.git"

        if ssh lucidia-pi "$clone_cmd" &>/dev/null; then
            test_pass "Successfully cloned $repo"
        else
            test_fail "Failed to clone $repo"
        fi
    done
}

# ============================================================
# DEPLOYMENT TESTS
# ============================================================

test_deployment_scripts() {
    echo ""
    echo -e "${CYAN}━━━ Deployment Script Tests ━━━${NC}"

    local -A device_roles=(
        ["lucidia-pi"]="ops"
        ["alice-pi"]="ops"
        ["aria-pi"]="sim"
        ["octavia-pi"]="holo"
    )

    for device in "${!device_roles[@]}"; do
        local role="${device_roles[$device]}"

        test_start "Deployment script for $device ($role role)"

        if ssh "$device" "test -x /opt/blackroad/scripts/deploy-${role}.sh"; then
            test_pass "deploy-${role}.sh exists and is executable on $device"
        else
            test_fail "deploy-${role}.sh not found on $device"
        fi
    done
}

test_manual_deployment() {
    echo ""
    echo -e "${CYAN}━━━ Manual Deployment Tests ━━━${NC}"

    test_start "Manual deployment to lucidia-pi"

    # Create test payload
    local test_payload=$(cat <<EOF
{
  "repository": "BlackRoad-OS/test-deploy",
  "branch": "main",
  "commit": "test-$(date +%s)",
  "task": "deploy"
}
EOF
)

    # Get webhook secret
    local webhook_secret=$(ssh lucidia-pi "sudo grep WEBHOOK_SECRET /opt/blackroad/agent/config.env 2>/dev/null | cut -d= -f2 | tr -d '\"'" || echo "changeme")

    # Send test webhook
    local response=$(ssh lucidia-pi "curl -s -X POST http://localhost:9001/deploy \
        -H 'Content-Type: application/json' \
        -H 'X-Webhook-Secret: $webhook_secret' \
        -d '$test_payload'" 2>/dev/null || echo "")

    if echo "$response" | grep -q "accepted"; then
        test_pass "Manual deployment accepted on lucidia-pi"

        # Wait a moment and check logs
        sleep 2
        if ssh lucidia-pi "sudo tail -5 /opt/blackroad/workspace/logs/webhook.log | grep -q 'Received deployment'" 2>/dev/null; then
            test_pass "Deployment logged on lucidia-pi"
        else
            test_fail "Deployment not logged on lucidia-pi"
        fi
    else
        test_fail "Manual deployment failed on lucidia-pi: $response"
    fi
}

# ============================================================
# CLOUDFLARE TESTS
# ============================================================

test_cloudflare_worker() {
    echo ""
    echo -e "${CYAN}━━━ Cloudflare Worker Tests ━━━${NC}"

    test_start "wrangler CLI installed"
    if command -v wrangler &>/dev/null; then
        test_pass "wrangler CLI found"
    else
        test_fail "wrangler CLI not found (install: npm install -g wrangler)"
        return
    fi

    test_start "wrangler authentication"
    if wrangler whoami &>/dev/null; then
        test_pass "wrangler authenticated"
    else
        test_skip "wrangler not authenticated (run: wrangler login)"
    fi

    # Check if worker config exists
    test_start "Worker configuration exists"
    if [[ -f "$HOME/wrangler.toml" ]] && [[ -f "$HOME/blackroad-deploy-worker.js" ]]; then
        test_pass "Worker files found"
    else
        test_fail "Worker files missing"
    fi
}

# ============================================================
# INTEGRATION TESTS
# ============================================================

test_full_pipeline() {
    echo ""
    echo -e "${CYAN}━━━ Full Pipeline Integration Tests ━━━${NC}"

    test_start "Create test repository"

    local test_repo_name="blackroad-test-$(date +%s)"
    local test_repo_dir="/tmp/$test_repo_name"

    # Create test repo locally
    rm -rf "$test_repo_dir"
    mkdir -p "$test_repo_dir"
    cd "$test_repo_dir"

    cat > README.md << EOF
# BlackRoad Test Repository

Created: $(date)
Test ID: $test_repo_name
EOF

    cat > frontend/App.jsx << EOF
// Test frontend file
export default function App() {
  return <div>BlackRoad Test</div>
}
EOF

    cat > backend/api.js << EOF
// Test backend file
const express = require('express')
const app = express()
app.get('/', (req, res) => res.send('BlackRoad Test API'))
EOF

    cat > tests/example.test.js << EOF
// Test file
test('example', () => {
  expect(true).toBe(true)
})
EOF

    git init
    git add .
    git commit -m "Initial test commit"

    test_pass "Created test repository: $test_repo_name"

    # Save test repo info
    echo "$test_repo_name" > "$RESULTS_DIR/test_repo.txt"

    cd - &>/dev/null
}

# ============================================================
# MANUAL CONTROL TESTS
# ============================================================

test_manual_controls() {
    echo ""
    echo -e "${CYAN}━━━ Manual Control Tests ━━━${NC}"

    # Test blackroad-cli
    test_start "blackroad-cli tool"
    if [[ -x "$HOME/blackroad-cli.sh" ]]; then
        test_pass "blackroad-cli.sh is executable"
    else
        test_fail "blackroad-cli.sh not found or not executable"
    fi

    # Test br-ssh (if exists)
    test_start "br-ssh operator tool"
    if [[ -x "$HOME/blackroad-backpack/operator/br-ssh" ]] 2>/dev/null; then
        test_pass "br-ssh tool found"
    else
        test_skip "br-ssh tool not yet installed"
    fi

    # Test br-mesh (if exists)
    test_start "br-mesh operator tool"
    if [[ -x "$HOME/blackroad-backpack/operator/br-mesh" ]] 2>/dev/null; then
        test_pass "br-mesh tool found"
    else
        test_skip "br-mesh tool not yet installed"
    fi
}

# ============================================================
# GENERATE REPORT
# ============================================================

generate_report() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}                    TEST SUMMARY${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo "  Total Tests:   $TOTAL_TESTS"
    echo -e "  ${GREEN}Passed:        $PASSED_TESTS${NC}"
    echo -e "  ${RED}Failed:        $FAILED_TESTS${NC}"
    echo -e "  ${YELLOW}Skipped:       $SKIPPED_TESTS${NC}"
    echo "  Success Rate:  $success_rate%"
    echo ""

    # Create JSON report
    cat > "$RESULTS_DIR/report.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "total": $TOTAL_TESTS,
  "passed": $PASSED_TESTS,
  "failed": $FAILED_TESTS,
  "skipped": $SKIPPED_TESTS,
  "success_rate": $success_rate
}
EOF

    # Create markdown report
    cat > "$RESULTS_DIR/REPORT.md" << EOF
# BlackRoad Test Report

**Date:** $(date)
**Version:** $VERSION

## Summary

- **Total Tests:** $TOTAL_TESTS
- **Passed:** ✅ $PASSED_TESTS
- **Failed:** ❌ $FAILED_TESTS
- **Skipped:** ⊘ $SKIPPED_TESTS
- **Success Rate:** $success_rate%

## Results

See \`test.log\` for detailed output.

## Files

- \`report.json\` - Machine-readable results
- \`test.log\` - Full test log
- \`test_repo.txt\` - Test repository name (if created)
- \`repo_count.txt\` - Number of BlackRoad repos found

EOF

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  📊 Full report: $RESULTS_DIR/REPORT.md"
    echo "  📝 Detailed log: $LOG_FILE"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "  ${GREEN}✓ All tests passed! System ready for deployment.${NC}"
    else
        echo -e "  ${RED}✗ Some tests failed. Review logs and fix issues.${NC}"
    fi

    echo ""
}

# ============================================================
# MAIN TEST RUNNER
# ============================================================

run_all_tests() {
    init_tests

    test_device_connectivity
    test_device_requirements
    test_webhook_receivers
    test_github_access
    test_clone_repositories
    test_deployment_scripts
    test_manual_deployment
    test_cloudflare_worker
    test_manual_controls
    test_full_pipeline

    generate_report
}

# Interactive menu
show_menu() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║  🖤🛣️  BlackRoad End-to-End Test Suite v1.0.0        ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo "Select test category:"
    echo ""
    echo "  [1] Run ALL Tests (comprehensive)"
    echo "  [2] Device Tests Only"
    echo "  [3] Repository Tests Only"
    echo "  [4] Deployment Tests Only"
    echo "  [5] Cloudflare Tests Only"
    echo "  [6] Manual Control Tests Only"
    echo "  [7] Quick Smoke Test"
    echo ""
    echo "  [v] View Last Results"
    echo "  [q] Quit"
    echo ""
    read -rp "Choice: " choice

    case "$choice" in
        1)
            run_all_tests
            ;;
        2)
            init_tests
            test_device_connectivity
            test_device_requirements
            test_webhook_receivers
            generate_report
            ;;
        3)
            init_tests
            test_github_access
            test_clone_repositories
            generate_report
            ;;
        4)
            init_tests
            test_deployment_scripts
            test_manual_deployment
            generate_report
            ;;
        5)
            init_tests
            test_cloudflare_worker
            generate_report
            ;;
        6)
            init_tests
            test_manual_controls
            generate_report
            ;;
        7)
            init_tests
            test_device_connectivity
            test_github_access
            test_manual_controls
            generate_report
            ;;
        v|V)
            if [[ -d "$TEST_DIR/results" ]]; then
                local latest=$(ls -t "$TEST_DIR/results" | head -1)
                if [[ -f "$TEST_DIR/results/$latest/REPORT.md" ]]; then
                    cat "$TEST_DIR/results/$latest/REPORT.md"
                    echo ""
                    read -rp "Press ENTER to continue..."
                fi
            fi
            show_menu
            ;;
        q|Q)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            sleep 1
            show_menu
            ;;
    esac

    read -rp "Press ENTER to return to menu..."
    show_menu
}

# Main
case "${1:-menu}" in
    all)
        run_all_tests
        ;;
    devices)
        init_tests
        test_device_connectivity
        test_device_requirements
        test_webhook_receivers
        generate_report
        ;;
    repos)
        init_tests
        test_github_access
        test_clone_repositories
        generate_report
        ;;
    deploy)
        init_tests
        test_deployment_scripts
        test_manual_deployment
        generate_report
        ;;
    menu|*)
        show_menu
        ;;
esac
