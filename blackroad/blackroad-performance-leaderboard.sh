#!/bin/bash
# BlackRoad Claude Agent Performance Leaderboard
set -e

LEADERBOARD_DB="$HOME/.blackroad/leaderboard/stats.db"
GREEN='\033[0;32m'
GOLD='\033[38;5;220m'
NC='\033[0m'

init() {
    mkdir -p "$(dirname "$LEADERBOARD_DB")"
    sqlite3 "$LEADERBOARD_DB" "CREATE TABLE IF NOT EXISTS agents (id TEXT PRIMARY KEY, name TEXT, points INT DEFAULT 0, rank INT);"
    echo -e "${GREEN}Leaderboard initialized!${NC}"
}

show() {
    echo -e "${GOLD}🏆 TOP CLAUDE AGENTS 🏆${NC}"
    sqlite3 -column "$LEADERBOARD_DB" "SELECT * FROM agents ORDER BY points DESC LIMIT 10;" 2>/dev/null || echo "No agents yet"
}

case "${1:-help}" in
    init) init ;;
    show) show ;;
    *) echo "Usage: $0 {init|show}" ;;
esac
