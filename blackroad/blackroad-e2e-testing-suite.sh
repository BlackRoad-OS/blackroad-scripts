#!/bin/bash
# BlackRoad E2E Testing Suite
# Comprehensive end-to-end testing for all deployment pipelines

set -e

SUITE_VERSION="1.0.0"
LOG_DIR="$HOME/.blackroad/e2e-tests"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/e2e-test-$TIMESTAMP.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

# Logging
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_success() {
    log "${GREEN}✅ $1${NC}"
}

log_error() {
    log "${RED}❌ $1${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Test Results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test Framework
run_test() {
    local test_name="$1"
    local test_command="$2"

    log_info "Running: $test_name"

    if eval "$test_command" >> "$LOG_FILE" 2>&1; then
        log_success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "$test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

run_test_skip_on_fail() {
    local test_name="$1"
    local test_command="$2"

    log_info "Running: $test_name (non-critical)"

    if eval "$test_command" >> "$LOG_FILE" 2>&1; then
        log_success "$test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_warning "$test_name (skipped)"
        ((TESTS_SKIPPED++))
        return 1
    fi
}

# ============================================
# TEST SUITES
# ============================================

test_github_connectivity() {
    log "\n${BLUE}=== GITHUB CONNECTIVITY TESTS ===${NC}"

    run_test "GitHub: Authentication status" \
        "gh auth status"

    run_test "GitHub: List BlackRoad-OS repos" \
        "gh repo list BlackRoad-OS --limit 1 --json name"

    run_test "GitHub: API rate limit check" \
        "gh api rate_limit"
}

test_cloudflare_connectivity() {
    log "\n${BLUE}=== CLOUDFLARE CONNECTIVITY TESTS ===${NC}"

    run_test_skip_on_fail "Cloudflare: Wrangler authentication" \
        "wrangler whoami"

    run_test_skip_on_fail "Cloudflare: List Pages projects" \
        "wrangler pages project list --json | jq -e 'length > 0'"
}

test_pi_devices() {
    log "\n${BLUE}=== RASPBERRY PI DEVICE TESTS ===${NC}"

    local pi_devices=(
        "192.168.4.38:lucidia"
        "192.168.4.64:blackroad-pi"
        "192.168.4.99:lucidia-alt"
    )

    for device in "${pi_devices[@]}"; do
        IFS=':' read -r ip name <<< "$device"
        run_test_skip_on_fail "Pi Device: $name ($ip) ping test" \
            "ping -c 1 -W 2 $ip"
    done
}

test_port_8080_services() {
    log "\n${BLUE}=== PORT 8080 SERVICE TESTS ===${NC}"

    run_test_skip_on_fail "Port 8080: iPhone Koder (192.168.4.68:8080)" \
        "nc -z -w 2 192.168.4.68 8080"

    run_test_skip_on_fail "Port 8080: Local service (127.0.0.1:8080)" \
        "nc -z -w 2 127.0.0.1 8080"
}

test_memory_system() {
    log "\n${BLUE}=== MEMORY SYSTEM TESTS ===${NC}"

    run_test "Memory System: Script exists" \
        "test -f $HOME/memory-system.sh"

    run_test_skip_on_fail "Memory System: Summary command" \
        "$HOME/memory-system.sh summary | grep -q 'Session'"

    run_test "Memory System: Memory directory exists" \
        "test -d $HOME/.blackroad/memory"
}

test_deployment_pipeline() {
    log "\n${BLUE}=== DEPLOYMENT PIPELINE TESTS ===${NC}"

    # Test that critical deployment scripts exist
    local scripts=(
        "memory-system.sh"
        "blackroad-codex-verification-suite.sh"
        "memory-realtime-context.sh"
    )

    for script in "${scripts[@]}"; do
        run_test "Deployment: $script exists" \
            "test -f $HOME/$script"
    done
}

test_git_workflow() {
    log "\n${BLUE}=== GIT WORKFLOW TESTS ===${NC}"

    run_test "Git: Version check" \
        "git --version"

    run_test "Git: Config user.name" \
        "git config user.name"

    run_test "Git: Config user.email" \
        "git config user.email"
}

test_nodejs_toolchain() {
    log "\n${BLUE}=== NODE.JS TOOLCHAIN TESTS ===${NC}"

    run_test_skip_on_fail "Node.js: Version check" \
        "node --version"

    run_test_skip_on_fail "npm: Version check" \
        "npm --version"

    run_test_skip_on_fail "pnpm: Version check" \
        "pnpm --version"
}

test_docker_environment() {
    log "\n${BLUE}=== DOCKER ENVIRONMENT TESTS ===${NC}"

    run_test_skip_on_fail "Docker: Version check" \
        "docker --version"

    run_test_skip_on_fail "Docker: Daemon running" \
        "docker ps"
}

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    log "${BLUE}╔════════════════════════════════════════════════╗${NC}"
    log "${BLUE}║  BlackRoad E2E Testing Suite v$SUITE_VERSION          ║${NC}"
    log "${BLUE}╚════════════════════════════════════════════════╝${NC}"
    log ""
    log "Test session: $TIMESTAMP"
    log "Log file: $LOG_FILE"
    log ""

    # Run all test suites
    test_github_connectivity
    test_cloudflare_connectivity
    test_pi_devices
    test_port_8080_services
    test_memory_system
    test_deployment_pipeline
    test_git_workflow
    test_nodejs_toolchain
    test_docker_environment

    # Summary
    log "\n${BLUE}═══════════════════════════════════════════════${NC}"
    log "${BLUE}TEST SUMMARY${NC}"
    log "${BLUE}═══════════════════════════════════════════════${NC}"
    log "${GREEN}Passed:  $TESTS_PASSED${NC}"
    log "${RED}Failed:  $TESTS_FAILED${NC}"
    log "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
    log "Total:   $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
    log ""

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All critical tests passed!"
        return 0
    else
        log_error "Some tests failed. Check $LOG_FILE for details."
        return 1
    fi
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
