#!/bin/bash
# BlackRoad Fork Orchestrator
# Automated forking + enhancement with collaboration & memory logging

TRACKER="$HOME/blackroad-sovereignty-fork-tracker.sh"
MY_CLAUDE="${MY_CLAUDE:-cecilia-sovereignty-forker-$(date +%s)}"

# Collaboration: Log to memory before any major action
log_to_memory() {
    local context="$1"
    local message="$2"
    local tags="${3:-sovereignty,forking}"

    ~/memory-system.sh log updated "$context" "$message" "$tags"
}

# Collaboration: Check for conflicts before forking
check_collaboration() {
    echo "🤝 Checking for other active Claude instances..."
    ~/memory-collaboration-dashboard.sh compact
}

# Fork a single repo with full workflow
fork_and_enhance() {
    local fork_id="$1"
    local org="${2:-BlackRoad-OS}"

    # Get repo details
    local repo_info=$(sqlite3 "$HOME/.blackroad/sovereignty-forks.db" \
        "SELECT category, component, original_repo, license FROM forks WHERE id=$fork_id;")

    local category=$(echo "$repo_info" | cut -d'|' -f1)
    local component=$(echo "$repo_info" | cut -d'|' -f2)
    local original_repo=$(echo "$repo_info" | cut -d'|' -f3)
    local license=$(echo "$repo_info" | cut -d'|' -f4)

    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  🔱 FORKING: [$fork_id] $component"
    echo "═══════════════════════════════════════════════════════"
    echo "  Category: $category"
    echo "  Original: $original_repo"
    echo "  License:  $license"
    echo "  Target:   $org"
    echo "═══════════════════════════════════════════════════════"
    echo ""

    # Log intention to memory (collaboration)
    log_to_memory "fork-intention" "[$MY_CLAUDE] Starting fork #$fork_id: $component ($category) to $org" "forking,collaboration,$category"

    # Fork the repo
    $TRACKER fork "$fork_id" "$org"
    local fork_status=$?

    if [ $fork_status -ne 0 ]; then
        echo "❌ Fork failed for #$fork_id: $component"
        log_to_memory "fork-failed" "[$MY_CLAUDE] Fork FAILED #$fork_id: $component" "forking,error,$category"
        return 1
    fi

    # Enhance with BlackRoad branding
    echo ""
    echo "✨ Enhancing with BlackRoad branding..."
    $TRACKER enhance "$fork_id"
    local enhance_status=$?

    if [ $enhance_status -ne 0 ]; then
        echo "⚠️  Enhancement failed for #$fork_id: $component"
        log_to_memory "enhance-failed" "[$MY_CLAUDE] Enhancement FAILED #$fork_id: $component (fork succeeded)" "enhancing,error,$category"
        return 1
    fi

    # Log completion to memory
    log_to_memory "fork-completed" "[$MY_CLAUDE] Successfully forked & enhanced #$fork_id: $component ($category). License: $license. Now available in $org." "forking,completed,$category"

    echo ""
    echo "✅ COMPLETED: #$fork_id - $component"
    echo ""

    return 0
}

# Fork entire category
fork_category_workflow() {
    local category="$1"
    local org="${2:-BlackRoad-OS}"

    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  🔱 FORKING CATEGORY: $category"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    # Check collaboration
    check_collaboration

    # Get all pending repos in category
    local fork_ids=$(sqlite3 "$HOME/.blackroad/sovereignty-forks.db" \
        "SELECT id FROM forks WHERE category='$category' AND fork_status='pending' ORDER BY priority;")

    local total=$(echo "$fork_ids" | wc -l | tr -d ' ')
    local count=0

    log_to_memory "category-fork-start" "[$MY_CLAUDE] Starting category fork: $category ($total repos)" "forking,$category"

    for fork_id in $fork_ids; do
        ((count++))
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Progress: $count / $total"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        fork_and_enhance "$fork_id" "$org"

        # Rate limiting: 2 second delay between forks
        if [ $count -lt $total ]; then
            echo "⏱️  Rate limiting (2s)..."
            sleep 2
        fi
    done

    log_to_memory "category-fork-complete" "[$MY_CLAUDE] Completed category fork: $category ($count/$total repos succeeded)" "forking,completed,$category"

    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  ✅ CATEGORY COMPLETE: $category"
    echo "║  📊 Forked: $count repos"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
}

# Fork by priority (top N)
fork_priority() {
    local limit="${1:-10}"
    local org="${2:-BlackRoad-OS}"

    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  🔥 FORKING TOP $limit PRIORITY REPOS"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    check_collaboration

    local fork_ids=$(sqlite3 "$HOME/.blackroad/sovereignty-forks.db" \
        "SELECT id FROM forks WHERE fork_status='pending' ORDER BY priority LIMIT $limit;")

    local count=0

    log_to_memory "priority-fork-start" "[$MY_CLAUDE] Starting priority fork: top $limit repos" "forking,priority"

    for fork_id in $fork_ids; do
        ((count++))
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Priority: $count / $limit"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        fork_and_enhance "$fork_id" "$org"

        if [ $count -lt $limit ]; then
            echo "⏱️  Rate limiting (2s)..."
            sleep 2
        fi
    done

    log_to_memory "priority-fork-complete" "[$MY_CLAUDE] Completed priority fork: $count repos" "forking,completed,priority"

    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  ✅ PRIORITY FORK COMPLETE"
    echo "║  📊 Forked: $count repos"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
}

# Fork ALL pending repos (full automation)
fork_all() {
    local org="${1:-BlackRoad-OS}"

    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  🚀 FORKING ALL 105 SOVEREIGNTY REPOS"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    check_collaboration

    local total=$(sqlite3 "$HOME/.blackroad/sovereignty-forks.db" \
        "SELECT COUNT(*) FROM forks WHERE fork_status='pending';")

    echo "⚠️  WARNING: This will fork $total repositories!"
    echo "⚠️  Estimated time: ~$(($total * 15 / 60)) minutes"
    echo ""

    log_to_memory "full-fork-start" "[$MY_CLAUDE] Starting FULL fork: all $total repos to $org" "forking,full-automation"

    local fork_ids=$(sqlite3 "$HOME/.blackroad/sovereignty-forks.db" \
        "SELECT id FROM forks WHERE fork_status='pending' ORDER BY priority;")

    local count=0
    local succeeded=0
    local failed=0

    for fork_id in $fork_ids; do
        ((count++))
        echo ""
        echo "╔═══════════════════════════════════════════════════════╗"
        echo "║  📊 PROGRESS: $count / $total"
        echo "║  ✅ Succeeded: $succeeded"
        echo "║  ❌ Failed: $failed"
        echo "╚═══════════════════════════════════════════════════════╝"
        echo ""

        if fork_and_enhance "$fork_id" "$org"; then
            ((succeeded++))
        else
            ((failed++))
        fi

        # Progress checkpoint every 10 repos
        if [ $(($count % 10)) -eq 0 ]; then
            log_to_memory "fork-checkpoint" "[$MY_CLAUDE] Fork checkpoint: $count/$total complete ($succeeded succeeded, $failed failed)" "forking,checkpoint"

            echo ""
            echo "🔄 Checkpoint: $count/$total repos processed"
            $TRACKER stats
            echo ""
        fi

        # Rate limiting
        if [ $count -lt $total ]; then
            sleep 2
        fi
    done

    log_to_memory "full-fork-complete" "[$MY_CLAUDE] COMPLETED full fork: $total repos processed ($succeeded succeeded, $failed failed)" "forking,completed,full-automation"

    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  🎉 FULL FORK COMPLETE!"
    echo "║  📊 Total: $total"
    echo "║  ✅ Succeeded: $succeeded"
    echo "║  ❌ Failed: $failed"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    $TRACKER stats
}

# Show status with collaboration check
status() {
    check_collaboration
    echo ""
    $TRACKER stats
    echo ""
    echo "🧠 Memory System Status:"
    ~/memory-system.sh summary
}

# Main command router
case "${1:-help}" in
    fork)
        fork_and_enhance "$2" "${3:-BlackRoad-OS}"
        ;;
    category)
        fork_category_workflow "$2" "${3:-BlackRoad-OS}"
        ;;
    priority)
        fork_priority "${2:-10}" "${3:-BlackRoad-OS}"
        ;;
    all)
        fork_all "${2:-BlackRoad-OS}"
        ;;
    status)
        status
        ;;
    collab)
        check_collaboration
        ;;
    *)
        cat <<HELP
╔═══════════════════════════════════════════════════════╗
║  🔱 BLACKROAD FORK ORCHESTRATOR                      ║
║  Automated forking with collaboration & memory       ║
╚═══════════════════════════════════════════════════════╝

Usage:
  $0 fork <id> [org]         - Fork & enhance single repo
  $0 category <name> [org]   - Fork & enhance entire category
  $0 priority [N] [org]      - Fork top N priority repos (default 10)
  $0 all [org]               - Fork ALL 105 repos (full automation)
  $0 status                  - Show status + collaboration check
  $0 collab                  - Check collaboration dashboard

Examples:
  $0 fork 1                  # Fork Keycloak
  $0 category Identity       # Fork all identity repos
  $0 priority 20             # Fork top 20 priority repos
  $0 all BlackRoad-OS        # Fork everything to BlackRoad-OS

Features:
  ✅ Automatic memory logging (collaboration)
  ✅ Conflict detection (other Claude instances)
  ✅ Rate limiting (2s between forks)
  ✅ Progress checkpoints
  ✅ BlackRoad branding automation
  ✅ Full statistics tracking

Current Session: $MY_CLAUDE
HELP
        ;;
esac
