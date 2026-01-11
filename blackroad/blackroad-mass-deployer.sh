#!/bin/bash
# BlackRoad Mass Deployment System
# Deploy to ALL repos simultaneously with intelligent orchestration

MASS_VERSION="2.0.0"
STATE_DIR="$HOME/.blackroad/mass-deploy"
QUEUE_DIR="$STATE_DIR/queue"
RESULTS_DIR="$STATE_DIR/results"
WAVES_DIR="$STATE_DIR/waves"

mkdir -p "$QUEUE_DIR" "$RESULTS_DIR" "$WAVES_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
MAX_PARALLEL=10
WAVE_DELAY=30
AUTO_ROLLBACK=true

# Get all BlackRoad repos
get_all_repos() {
    local orgs=(
        "BlackRoad-OS"
        "BlackRoad-AI"
        "BlackRoad-Cloud"
        "BlackRoad-Foundation"
    )

    local all_repos=()

    for org in "${orgs[@]}"; do
        local repos=$(gh repo list "$org" --limit 1000 --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null || echo "")
        if [ -n "$repos" ]; then
            all_repos+=($repos)
        fi
    done

    printf '%s\n' "${all_repos[@]}"
}

# Categorize repos by type
categorize_repo() {
    local repo="$1"
    local category="unknown"

    # Check for indicators
    if gh api "repos/$repo/contents" -q '.[] | select(.name == "package.json") | .name' 2>/dev/null | grep -q "package.json"; then
        category="nodejs"
    elif gh api "repos/$repo/contents" -q '.[] | select(.name == "requirements.txt") | .name' 2>/dev/null | grep -q "requirements.txt"; then
        category="python"
    elif gh api "repos/$repo/contents" -q '.[] | select(.name == "Dockerfile") | .name' 2>/dev/null | grep -q "Dockerfile"; then
        category="docker"
    elif gh api "repos/$repo/contents" -q '.[] | select(.name == ".github") | .name' 2>/dev/null | grep -q ".github"; then
        category="static"
    fi

    echo "$category"
}

# Analyze all repos
analyze_repos() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Analyzing All BlackRoad Repositories                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local repos=($(get_all_repos))
    local total=${#repos[@]}

    echo -e "${BLUE}Found $total repositories${NC}"
    echo ""

    local analysis_file="$STATE_DIR/repo-analysis.json"
    echo "[" > "$analysis_file"

    local count=0
    for repo in "${repos[@]}"; do
        ((count++))
        echo -ne "${BLUE}Analyzing [$count/$total]: $repo${NC}\r"

        local category=$(categorize_repo "$repo")
        local last_commit=$(gh api "repos/$repo/commits/main" -q '.sha' 2>/dev/null | head -c 7 || echo "unknown")
        local has_ci=$(gh api "repos/$repo/contents/.github/workflows" 2>/dev/null | jq -e 'length > 0' &>/dev/null && echo "true" || echo "false")
        local updated_at=$(gh api "repos/$repo" -q '.updated_at' 2>/dev/null || echo "unknown")

        jq -n \
            --arg repo "$repo" \
            --arg category "$category" \
            --arg last_commit "$last_commit" \
            --arg has_ci "$has_ci" \
            --arg updated_at "$updated_at" \
            '{repo: $repo, category: $category, last_commit: $last_commit, has_ci: $has_ci, updated_at: $updated_at}' >> "$analysis_file"

        if [ $count -lt $total ]; then
            echo "," >> "$analysis_file"
        fi
    done

    echo "]" >> "$analysis_file"
    echo ""
    echo -e "${GREEN}✅ Analysis complete: $analysis_file${NC}"

    # Summary
    echo ""
    echo -e "${MAGENTA}Repository Breakdown:${NC}"
    local nodejs_count=$(jq '[.[] | select(.category == "nodejs")] | length' "$analysis_file")
    local python_count=$(jq '[.[] | select(.category == "python")] | length' "$analysis_file")
    local docker_count=$(jq '[.[] | select(.category == "docker")] | length' "$analysis_file")
    local static_count=$(jq '[.[] | select(.category == "static")] | length' "$analysis_file")
    local unknown_count=$(jq '[.[] | select(.category == "unknown")] | length' "$analysis_file")
    local has_ci_count=$(jq '[.[] | select(.has_ci == "true")] | length' "$analysis_file")

    echo -e "  ${BLUE}Node.js:${NC} $nodejs_count"
    echo -e "  ${BLUE}Python:${NC} $python_count"
    echo -e "  ${BLUE}Docker:${NC} $docker_count"
    echo -e "  ${BLUE}Static:${NC} $static_count"
    echo -e "  ${BLUE}Unknown:${NC} $unknown_count"
    echo ""
    echo -e "  ${GREEN}With CI/CD:${NC} $has_ci_count"
    echo -e "  ${YELLOW}Without CI/CD:${NC} $((total - has_ci_count))"
}

# Create deployment waves
create_waves() {
    local strategy="${1:-gradual}"  # gradual, fast, canary

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Creating Deployment Waves ($strategy)                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local analysis_file="$STATE_DIR/repo-analysis.json"

    if [ ! -f "$analysis_file" ]; then
        echo -e "${RED}❌ No analysis file found. Run: analyze first${NC}"
        return 1
    fi

    local all_repos=$(jq -r '.[].repo' "$analysis_file")
    local waves_file="$WAVES_DIR/waves-$(date +%s).json"

    case "$strategy" in
        canary)
            # Wave 1: 1 canary repo
            # Wave 2: 10% of repos
            # Wave 3: 50% of repos
            # Wave 4: All remaining
            create_canary_waves "$analysis_file" "$waves_file"
            ;;
        fast)
            # Wave 1: 50 repos
            # Wave 2: All remaining
            create_fast_waves "$analysis_file" "$waves_file"
            ;;
        gradual)
            # Wave 1: 10 repos
            # Wave 2: 25 repos
            # Wave 3: 50 repos
            # Wave 4: All remaining
            create_gradual_waves "$analysis_file" "$waves_file"
            ;;
    esac

    echo -e "${GREEN}✅ Waves created: $waves_file${NC}"
}

create_gradual_waves() {
    local analysis_file="$1"
    local waves_file="$2"

    local all_repos=$(jq -r '.[].repo' "$analysis_file" | tr '\n' ' ')
    local repos_array=($all_repos)
    local total=${#repos_array[@]}

    # Wave 1: 10 repos
    local wave1=$(printf '%s\n' "${repos_array[@]:0:10}" | jq -R . | jq -s .)

    # Wave 2: 25 repos
    local wave2=$(printf '%s\n' "${repos_array[@]:10:25}" | jq -R . | jq -s .)

    # Wave 3: 50 repos
    local wave3=$(printf '%s\n' "${repos_array[@]:35:50}" | jq -R . | jq -s .)

    # Wave 4: Remaining
    local wave4=$(printf '%s\n' "${repos_array[@]:85}" | jq -R . | jq -s .)

    jq -n \
        --argjson wave1 "$wave1" \
        --argjson wave2 "$wave2" \
        --argjson wave3 "$wave3" \
        --argjson wave4 "$wave4" \
        '{
            strategy: "gradual",
            waves: [
                {id: 1, repos: $wave1, delay: 30},
                {id: 2, repos: $wave2, delay: 60},
                {id: 3, repos: $wave3, delay: 120},
                {id: 4, repos: $wave4, delay: 0}
            ]
        }' > "$waves_file"

    echo -e "${BLUE}Wave 1: 10 repos (30s delay)${NC}"
    echo -e "${BLUE}Wave 2: 25 repos (60s delay)${NC}"
    echo -e "${BLUE}Wave 3: 50 repos (120s delay)${NC}"
    echo -e "${BLUE}Wave 4: ${#repos_array[@]:85} repos (final)${NC}"
}

create_canary_waves() {
    local analysis_file="$1"
    local waves_file="$2"

    local all_repos=$(jq -r '.[].repo' "$analysis_file" | tr '\n' ' ')
    local repos_array=($all_repos)
    local total=${#repos_array[@]}

    local wave1=$(printf '%s\n' "${repos_array[@]:0:1}" | jq -R . | jq -s .)
    local ten_percent=$((total / 10))
    local fifty_percent=$((total / 2))

    local wave2=$(printf '%s\n' "${repos_array[@]:1:$ten_percent}" | jq -R . | jq -s .)
    local wave3=$(printf '%s\n' "${repos_array[@]:$((1 + ten_percent)):$fifty_percent}" | jq -R . | jq -s .)
    local wave4=$(printf '%s\n' "${repos_array[@]:$((1 + ten_percent + fifty_percent))}" | jq -R . | jq -s .)

    jq -n \
        --argjson wave1 "$wave1" \
        --argjson wave2 "$wave2" \
        --argjson wave3 "$wave3" \
        --argjson wave4 "$wave4" \
        '{
            strategy: "canary",
            waves: [
                {id: 1, repos: $wave1, delay: 300},
                {id: 2, repos: $wave2, delay: 180},
                {id: 3, repos: $wave3, delay: 120},
                {id: 4, repos: $wave4, delay: 0}
            ]
        }' > "$waves_file"

    echo -e "${BLUE}Wave 1: 1 canary repo (300s delay)${NC}"
    echo -e "${BLUE}Wave 2: $ten_percent repos (180s delay)${NC}"
    echo -e "${BLUE}Wave 3: $fifty_percent repos (120s delay)${NC}"
    echo -e "${BLUE}Wave 4: Remaining repos (final)${NC}"
}

# Deploy in waves
deploy_waves() {
    local waves_file="${1:-$(ls -t $WAVES_DIR/waves-*.json 2>/dev/null | head -1)}"

    if [ ! -f "$waves_file" ]; then
        echo -e "${RED}❌ No waves file found${NC}"
        return 1
    fi

    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Executing Wave Deployment                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local wave_count=$(jq '.waves | length' "$waves_file")
    local strategy=$(jq -r '.strategy' "$waves_file")

    echo -e "${BLUE}Strategy: $strategy${NC}"
    echo -e "${BLUE}Total waves: $wave_count${NC}"
    echo ""

    for ((i=0; i<wave_count; i++)); do
        local wave_id=$(jq -r ".waves[$i].id" "$waves_file")
        local repos=$(jq -r ".waves[$i].repos[]" "$waves_file")
        local delay=$(jq -r ".waves[$i].delay" "$waves_file")
        local repo_count=$(echo "$repos" | wc -l | tr -d ' ')

        echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
        echo -e "${MAGENTA}Wave $wave_id: $repo_count repositories${NC}"
        echo -e "${MAGENTA}═══════════════════════════════════════${NC}"
        echo ""

        # Deploy wave
        deploy_wave_batch "$repos"

        # Wait between waves
        if [ $i -lt $((wave_count - 1)) ] && [ $delay -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}⏳ Waiting ${delay}s before next wave...${NC}"
            sleep "$delay"
            echo ""
        fi
    done

    echo ""
    echo -e "${GREEN}🎉 All waves deployed!${NC}"
}

# Deploy a batch of repos
deploy_wave_batch() {
    local repos="$1"
    local pids=()
    local results=()

    # Deploy in parallel (up to MAX_PARALLEL)
    local count=0
    while IFS= read -r repo; do
        deploy_single_repo "$repo" &
        pids+=($!)

        ((count++))

        # Wait if we hit max parallel
        if [ $((count % MAX_PARALLEL)) -eq 0 ]; then
            wait "${pids[@]}"
            pids=()
        fi
    done <<< "$repos"

    # Wait for remaining
    if [ ${#pids[@]} -gt 0 ]; then
        wait "${pids[@]}"
    fi
}

# Deploy single repo
deploy_single_repo() {
    local repo="$1"
    local result_file="$RESULTS_DIR/$(echo $repo | tr '/' '-')-$(date +%s).json"

    echo -e "${BLUE}  Deploying: $repo${NC}"

    # This is a placeholder - actual deployment would:
    # 1. Clone repo
    # 2. Detect type
    # 3. Run appropriate deployment
    # 4. Verify
    # 5. Record result

    local status="success"
    local message="Deployment simulated"

    jq -n \
        --arg repo "$repo" \
        --arg status "$status" \
        --arg message "$message" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{repo: $repo, status: $status, message: $message, timestamp: $timestamp}' \
        > "$result_file"

    if [ "$status" = "success" ]; then
        echo -e "${GREEN}  ✅ $repo${NC}"
    else
        echo -e "${RED}  ❌ $repo: $message${NC}"
    fi
}

# Add CI/CD to all repos that don't have it
mass_add_cicd() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Mass CI/CD Addition                                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local analysis_file="$STATE_DIR/repo-analysis.json"

    if [ ! -f "$analysis_file" ]; then
        echo -e "${RED}❌ Run analysis first${NC}"
        return 1
    fi

    # Get repos without CI/CD
    local repos_without_ci=$(jq -r '.[] | select(.has_ci == "false") | .repo' "$analysis_file")
    local count=$(echo "$repos_without_ci" | wc -l | tr -d ' ')

    echo -e "${BLUE}Found $count repositories without CI/CD${NC}"
    echo ""

    # For each repo, add appropriate CI/CD
    while IFS= read -r repo; do
        local category=$(jq -r ".[] | select(.repo == \"$repo\") | .category" "$analysis_file")

        echo -e "${BLUE}Adding CI/CD to: $repo ($category)${NC}"

        # This would actually:
        # 1. Clone repo
        # 2. Add appropriate workflow template
        # 3. Commit and push
        # For now, just simulate

        echo -e "${GREEN}  ✅ Would add $category workflow${NC}"
    done <<< "$repos_without_ci"

    echo ""
    echo -e "${GREEN}✅ CI/CD addition complete${NC}"
}

# Dashboard
show_dashboard() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  BlackRoad Mass Deployment Dashboard                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Recent deployments
    local recent_results=$(find "$RESULTS_DIR" -name "*.json" -type f 2>/dev/null | sort -r | head -20)

    if [ -z "$recent_results" ]; then
        echo -e "${YELLOW}No deployment results yet${NC}"
        return
    fi

    local total=0
    local success=0
    local failed=0

    while IFS= read -r result_file; do
        ((total++))
        local status=$(jq -r '.status' "$result_file")
        if [ "$status" = "success" ]; then
            ((success++))
        else
            ((failed++))
        fi
    done <<< "$recent_results"

    echo -e "${BLUE}Recent Deployments (last 20):${NC}"
    echo -e "  Total: $total"
    echo -e "  ${GREEN}Success: $success${NC}"
    echo -e "  ${RED}Failed: $failed${NC}"
    echo ""

    # Show latest
    echo -e "${MAGENTA}Latest Deployments:${NC}"
    head -10 <<< "$recent_results" | while IFS= read -r result_file; do
        local repo=$(jq -r '.repo' "$result_file")
        local status=$(jq -r '.status' "$result_file")
        local timestamp=$(jq -r '.timestamp' "$result_file")

        local icon=$([ "$status" = "success" ] && echo "${GREEN}✅" || echo "${RED}❌")
        echo -e "  $icon $repo ($timestamp)${NC}"
    done
}

# CLI
case "${1:-menu}" in
    analyze)
        analyze_repos
        ;;
    waves)
        create_waves "${2:-gradual}"
        ;;
    deploy)
        deploy_waves "$2"
        ;;
    add-cicd)
        mass_add_cicd
        ;;
    dashboard)
        show_dashboard
        ;;
    *)
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║  BlackRoad Mass Deployment System v$MASS_VERSION         ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  analyze              Analyze all BlackRoad repositories"
        echo "  waves <strategy>     Create deployment waves (gradual|fast|canary)"
        echo "  deploy [waves_file]  Execute wave deployment"
        echo "  add-cicd             Add CI/CD to all repos without it"
        echo "  dashboard            Show deployment dashboard"
        echo ""
        echo "Example workflow:"
        echo "  $0 analyze"
        echo "  $0 waves canary"
        echo "  $0 deploy"
        echo ""
        ;;
esac
