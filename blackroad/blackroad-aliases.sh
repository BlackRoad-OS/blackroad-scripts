#!/usr/bin/env bash
# BlackRoad Quick Access Aliases
# Source this file to get convenient shortcuts
# Usage: source ~/blackroad-aliases.sh

# Query shortcuts
alias br-agents='~/blackroad-query.sh agents'
alias br-tasks='~/blackroad-query.sh tasks'
alias br-infra='~/blackroad-query.sh infra'
alias br-collab='~/blackroad-query.sh collab'
alias br-browse='~/blackroad-query.sh browse'
alias br-stats='~/blackroad-query.sh stats'
alias br-query='~/blackroad-query.sh query'

# Leaderboard shortcuts
alias br-leaderboard='~/blackroad-agent-leaderboard.sh show'
alias br-profile='~/blackroad-agent-leaderboard.sh profile $MY_CLAUDE'
alias br-achievements='~/blackroad-agent-leaderboard.sh achievements $MY_CLAUDE'
alias br-live='~/blackroad-agent-leaderboard.sh live'

# Bot shortcuts
alias br-bots='~/blackroad-bot-connector.sh list'
alias br-connect='~/blackroad-bot-connector.sh auto-connect $MY_CLAUDE'
alias br-broadcast='~/blackroad-bot-connector.sh broadcast $MY_CLAUDE'

# Namespace shortcuts
alias br-map='~/blackroad-namespace-mapper.sh analyze'

# Memory shortcuts
alias br-memory='~/memory-system.sh summary'
alias br-log='~/memory-system.sh log'
alias br-til='~/memory-til-broadcast.sh broadcast'

# Collaboration shortcuts
alias br-dash='~/memory-collaboration-dashboard.sh compact'
alias br-sync='~/memory-realtime-context.sh live $MY_CLAUDE compact'

# Task marketplace shortcuts
alias br-task-list='~/memory-task-marketplace.sh list'
alias br-task-claim='~/memory-task-marketplace.sh claim'
alias br-task-complete='~/memory-task-marketplace.sh complete'

# Registry shortcuts
alias br-registry='~/blackroad-agent-registry.sh list'
alias br-register='~/blackroad-agent-registry.sh register'

# Quick helpers
alias br-init='~/claude-session-init.sh'
alias br-help='cat ~/BLACKROAD_SYSTEMS_COMPLETE_GUIDE.md'

# Color output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     ⚡ BLACKROAD ALIASES LOADED ⚡                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Quick Commands Available:${NC}"
echo -e "  ${CYAN}br-agents${NC}          - List all agents"
echo -e "  ${CYAN}br-tasks${NC}           - Show active tasks"
echo -e "  ${CYAN}br-infra${NC}           - Recent deployments"
echo -e "  ${CYAN}br-collab${NC}          - Collaboration feed"
echo -e "  ${CYAN}br-leaderboard${NC}     - Show rankings"
echo -e "  ${CYAN}br-profile${NC}         - Your profile"
echo -e "  ${CYAN}br-bots${NC}            - List bot connections"
echo -e "  ${CYAN}br-connect${NC}         - Auto-connect all bots"
echo -e "  ${CYAN}br-memory${NC}          - Memory summary"
echo -e "  ${CYAN}br-help${NC}            - Complete guide"
echo ""
echo -e "${GREEN}Current Agent: ${CYAN}${MY_CLAUDE:-not-set}${NC}"
echo ""
