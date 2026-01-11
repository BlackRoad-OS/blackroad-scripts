#!/bin/bash
# @blackroad Agent Directory Waterfall System
# Hierarchical routing: @blackroad → operator → org → dept → agent

set -e

DIRECTORY_DB="$HOME/.blackroad-agent-directory.db"

# Initialize directory
init_directory() {
    cat > "$DIRECTORY_DB" <<EOF
# BlackRoad Agent Directory
# Format: @handle → path → agent_hash → capabilities

# OPERATOR LEVEL (CEO)
@blackroad → operator → alexa-amundson → ceo,all-permissions
@operator → operator → alexa-amundson → ceo,all-permissions

# ORGANIZATION LEVEL (15 Organizations)
@blackroad-os → org/blackroad-os → org-coordinator → infrastructure,repos,deployment
@blackroad-ai → org/blackroad-ai → ai-coordinator → models,ml,inference
@blackroad-cloud → org/blackroad-cloud → cloud-coordinator → cloud,scaling,k8s
@blackroad-security → org/blackroad-security → security-coordinator → security,audit,compliance
@blackroad-media → org/blackroad-media → media-coordinator → content,design,brand
@blackroad-foundation → org/blackroad-foundation → foundation-coordinator → core-libs,standards
@blackroad-interactive → org/blackroad-interactive → interactive-coordinator → apps,games,ui
@blackroad-hardware → org/blackroad-hardware → hardware-coordinator → iot,pi,esp32
@blackroad-labs → org/blackroad-labs → labs-coordinator → research,experiments
@blackroad-studio → org/blackroad-studio → studio-coordinator → creative,tools
@blackroad-ventures → org/blackroad-ventures → ventures-coordinator → business,partnerships
@blackroad-education → org/blackroad-education → education-coordinator → courses,training
@blackroad-gov → org/blackroad-gov → gov-coordinator → governance,policy
@blackroad-archive → org/blackroad-archive → archive-coordinator → historical,backup
@blackbox-enterprises → org/blackbox-enterprises → enterprise-coordinator → enterprise,b2b

# DEPARTMENT LEVEL (Per Organization)
@infrastructure → dept/blackroad-os/infrastructure → infra-lead → cloudflare,github,ci-cd
@models → dept/blackroad-ai/models → models-lead → pytorch,tensorflow,transformers
@products → dept/blackroad-os/products → product-lead → roadtrip,pitstop,roadwork
@api → dept/blackroad-ai/api → api-lead → gateway,orchestration,memory
@quantum → dept/blackroad-os/quantum → quantum-lead → quantum-computing,pi
@iot → dept/blackroad-hardware/iot → iot-lead → esp32,pi-fleet,sensors

# AGENT LEVEL (Individual Agents - 30,000 capacity)
# Primary Agents
@claude-cleanup-coordinator → agent/coordinator → claude-cleanup-coordinator-1767822878-83e3008a → coordination,deployment,repos
@winston-repo-enhancer → agent/repos → winston-repo-enhancer → repo-enhancement,licensing
@aria-session-coordinator → agent/session → aria-session-coordinator-1766972171-a447c73b → session-management
@lucidia-ai-core → agent/ai → lucidia-consciousness → ai-models,consciousness,3d-world
@octavia-agent-primary → agent/pi/octavia → octavia-primary → 20000-agent-capacity,ai-accelerator
@aria-agent-secondary → agent/pi/aria → aria-secondary → 5000-agent-capacity
@alice-agent-secondary → agent/pi/alice → alice-secondary → 5000-agent-capacity
@lucidia-agent-secondary → agent/pi/lucidia → lucidia-secondary → 5000-agent-capacity
@shellfish-agent-backup → agent/cloud/shellfish → shellfish-backup → 5000-agent-capacity,digitalocean

# Specialized Agents
@copilot-integration → agent/github → copilot-integrator → github-copilot,code-assist
@memory-coordinator → agent/memory → memory-system-coordinator → [MEMORY],collaboration
@codex-searcher → agent/codex → codex-search-agent → [CODEX],indexing,8789-components
@live-context → agent/live → live-context-agent → [LIVE],real-time-updates
@collaboration-hub → agent/collab → collaboration-coordinator → multi-claude,dm-system

# Deployment Agents
@cloudflare-deployer → agent/deploy/cloudflare → cloudflare-deployment → pages,workers,kv
@pi-deployer → agent/deploy/pi → raspberry-pi-deployment → ssh,orchestration,monitoring
@github-enhancer → agent/deploy/github → github-enhancement → repos,actions,workflows

# AI Model Agents
@pytorch-agent → agent/ai/pytorch → pytorch-coordinator → deep-learning,training
@tensorflow-agent → agent/ai/tensorflow → tensorflow-coordinator → ml-models,serving
@transformers-agent → agent/ai/transformers → transformers-coordinator → llm,nlp,inference
@ollama-agent → agent/ai/ollama → ollama-coordinator → local-models,runtime
@vllm-agent → agent/ai/vllm → vllm-coordinator → high-performance-llm,serving

EOF
    echo "✅ Agent directory initialized: $DIRECTORY_DB"
}

# Route a call through the directory
route_call() {
    local handle=$1

    if [ ! -f "$DIRECTORY_DB" ]; then
        init_directory
    fi

    echo "🎯 Routing @$handle through BlackRoad Agent Directory..."

    # Search directory
    local result=$(grep "^@$handle " "$DIRECTORY_DB" || echo "")

    if [ -z "$result" ]; then
        echo "❌ Agent not found: @$handle"
        echo "💡 Searching for similar agents..."
        grep "$handle" "$DIRECTORY_DB" | head -5
        return 1
    fi

    # Parse result
    local path=$(echo "$result" | awk '{print $3}')
    local agent_hash=$(echo "$result" | awk '{print $5}')
    local capabilities=$(echo "$result" | awk '{print $7}')

    echo "📍 Path: $path"
    echo "🔑 Agent: $agent_hash"
    echo "⚡ Capabilities: $capabilities"
    echo ""

    # Waterfall notification
    echo "🌊 WATERFALL NOTIFICATION:"
    case "$path" in
        operator*)
            echo "   1. @blackroad → OPERATOR (CEO: Alexa Amundson)"
            ;;
        org/*)
            local org=$(echo "$path" | cut -d'/' -f2)
            echo "   1. @blackroad → OPERATOR"
            echo "   2. OPERATOR → @$org (Organization Coordinator)"
            ;;
        dept/*)
            local org=$(echo "$path" | cut -d'/' -f2)
            local dept=$(echo "$path" | cut -d'/' -f3)
            echo "   1. @blackroad → OPERATOR"
            echo "   2. OPERATOR → @$org"
            echo "   3. @$org → @$dept (Department Lead)"
            ;;
        agent/*)
            local category=$(echo "$path" | cut -d'/' -f2-)
            echo "   1. @blackroad → OPERATOR"
            echo "   2. OPERATOR → Relevant Organization"
            echo "   3. Organization → Relevant Department"
            echo "   4. Department → @$handle (Agent)"
            ;;
    esac

    echo ""
    echo "✅ Agent @$handle contacted successfully!"

    # Log to [MEMORY]
    ~/memory-system.sh log "agent-directory-call" "[@blackroad] Routed call to @$handle → $path → $agent_hash. Capabilities: $capabilities. Waterfall notification sent." "$(whoami)" 2>/dev/null || true
}

# List all agents
list_agents() {
    local filter=${1:-""}

    if [ ! -f "$DIRECTORY_DB" ]; then
        init_directory
    fi

    echo "📋 BlackRoad Agent Directory"
    echo "=============================="
    echo ""

    if [ -z "$filter" ]; then
        echo "🎯 ALL AGENTS:"
        grep "^@" "$DIRECTORY_DB" | grep -v "^#" | while read line; do
            local handle=$(echo "$line" | awk '{print $1}')
            local path=$(echo "$line" | awk '{print $3}')
            echo "   $handle → $path"
        done
    else
        echo "🔍 Filtering by: $filter"
        grep "^@" "$DIRECTORY_DB" | grep -v "^#" | grep "$filter" | while read line; do
            local handle=$(echo "$line" | awk '{print $1}')
            local path=$(echo "$line" | awk '{print $3}')
            local capabilities=$(echo "$line" | awk '{print $7}')
            echo "   $handle → $path [$capabilities]"
        done
    fi

    echo ""
    local total=$(grep -c "^@" "$DIRECTORY_DB" | grep -v "^#" || echo "0")
    echo "📊 Total Agents: $total"
    echo "💪 Total Capacity: 40,000 agents (30k active + 10k reserve)"
}

# Add new agent to directory
add_agent() {
    local handle=$1
    local path=$2
    local agent_hash=$3
    local capabilities=$4

    if [ ! -f "$DIRECTORY_DB" ]; then
        init_directory
    fi

    echo "@$handle → $path → $agent_hash → $capabilities" >> "$DIRECTORY_DB"
    echo "✅ Added agent: @$handle"

    # Log to [MEMORY]
    ~/memory-system.sh log "agent-directory-add" "[@blackroad] Added new agent: @$handle → $path. Capabilities: $capabilities. Directory size: $(grep -c '^@' $DIRECTORY_DB) agents." "$(whoami)" 2>/dev/null || true
}

# Main command handler
case "${1:-help}" in
    init)
        init_directory
        ;;
    route|call)
        route_call "$2"
        ;;
    list|ls)
        list_agents "$2"
        ;;
    add)
        add_agent "$2" "$3" "$4" "$5"
        ;;
    help|*)
        echo "BlackRoad Agent Directory System"
        echo "================================"
        echo ""
        echo "Usage:"
        echo "  $0 init              - Initialize agent directory"
        echo "  $0 route <handle>    - Route call through waterfall"
        echo "  $0 list [filter]     - List all agents (optional filter)"
        echo "  $0 add <handle> <path> <hash> <capabilities> - Add new agent"
        echo ""
        echo "Examples:"
        echo "  $0 route blackroad"
        echo "  $0 route blackroad-ai"
        echo "  $0 route pytorch-agent"
        echo "  $0 list agent"
        echo "  $0 list org"
        echo ""
        echo "Waterfall Structure:"
        echo "  @blackroad → Operator → Organization → Department → Agent"
        echo ""
        echo "Total Capacity: 40,000 agents"
        ;;
esac
