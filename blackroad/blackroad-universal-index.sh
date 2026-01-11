#!/bin/bash
# [INDEX] - BlackRoad Universal Asset Indexer
# Maintains real-time index of ALL BlackRoad infrastructure
# Version: 1.0.0

set -e

INDEX_DIR="$HOME/.blackroad/index"
INDEX_DB="$INDEX_DIR/assets.db"
CACHE_DIR="$INDEX_DIR/cache"
LOG_FILE="$INDEX_DIR/index.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize database
init_index() {
    echo -e "${BLUE}[INDEX]${NC} Initializing Universal Asset Index..."

    mkdir -p "$INDEX_DIR" "$CACHE_DIR"

    # Create SQLite database
    sqlite3 "$INDEX_DB" <<EOF
CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    url TEXT,
    status TEXT,
    owner TEXT,
    last_updated TEXT,
    metadata TEXT,
    hash TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS github_repos (
    id TEXT PRIMARY KEY,
    org TEXT NOT NULL,
    repo TEXT NOT NULL,
    url TEXT NOT NULL,
    description TEXT,
    language TEXT,
    stars INTEGER,
    updated_at TEXT,
    last_commit TEXT,
    last_commit_author TEXT,
    branch TEXT DEFAULT 'main',
    has_actions BOOLEAN,
    topics TEXT,
    FOREIGN KEY (id) REFERENCES assets(id)
);

CREATE TABLE IF NOT EXISTS cloudflare_resources (
    id TEXT PRIMARY KEY,
    resource_type TEXT NOT NULL,
    zone TEXT,
    name TEXT NOT NULL,
    url TEXT,
    status TEXT,
    deployment_url TEXT,
    last_deployed TEXT,
    environment TEXT,
    FOREIGN KEY (id) REFERENCES assets(id)
);

CREATE TABLE IF NOT EXISTS pi_services (
    id TEXT PRIMARY KEY,
    hostname TEXT NOT NULL,
    ip TEXT NOT NULL,
    service_name TEXT NOT NULL,
    port INTEGER,
    status TEXT,
    uptime TEXT,
    cpu_usage REAL,
    memory_usage REAL,
    last_checked TEXT,
    FOREIGN KEY (id) REFERENCES assets(id)
);

CREATE TABLE IF NOT EXISTS railway_projects (
    id TEXT PRIMARY KEY,
    project_name TEXT NOT NULL,
    service_name TEXT,
    url TEXT,
    status TEXT,
    environment TEXT,
    last_deployed TEXT,
    region TEXT,
    FOREIGN KEY (id) REFERENCES assets(id)
);

CREATE INDEX IF NOT EXISTS idx_asset_type ON assets(type);
CREATE INDEX IF NOT EXISTS idx_asset_status ON assets(status);
CREATE INDEX IF NOT EXISTS idx_asset_updated ON assets(last_updated);
CREATE INDEX IF NOT EXISTS idx_github_org ON github_repos(org);
CREATE INDEX IF NOT EXISTS idx_cloudflare_type ON cloudflare_resources(resource_type);
EOF

    echo -e "${GREEN}[INDEX]${NC} Database initialized at: $INDEX_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "universal-index" "Initialized [INDEX] system at $INDEX_DB" "coordination,index" 2>/dev/null || true
    fi
}

# Index GitHub repositories
index_github() {
    echo -e "${BLUE}[INDEX]${NC} Scanning GitHub repositories..."

    local orgs="BlackRoad-OS BlackRoad-AI BlackRoad-Archive BlackRoad-Cloud BlackRoad-Education BlackRoad-Foundation BlackRoad-Gov BlackRoad-Hardware BlackRoad-Interactive BlackRoad-Labs BlackRoad-Media BlackRoad-Security BlackRoad-Studio BlackRoad-Ventures Blackbox-Enterprises"

    local total_repos=0

    for org in $orgs; do
        echo -e "${CYAN}  Scanning org: $org${NC}"

        # Get repos via gh CLI
        gh repo list "$org" --limit 100 --json name,url,description,primaryLanguage,stargazerCount,updatedAt,defaultBranchRef 2>/dev/null | \
        jq -c '.[]' | while read -r repo; do
            local repo_name=$(echo "$repo" | jq -r '.name')
            local repo_url=$(echo "$repo" | jq -r '.url')
            local description=$(echo "$repo" | jq -r '.description // ""')
            local language=$(echo "$repo" | jq -r '.primaryLanguage.name // ""')
            local stars=$(echo "$repo" | jq -r '.stargazerCount // 0')
            local updated_at=$(echo "$repo" | jq -r '.updatedAt // ""')
            local branch=$(echo "$repo" | jq -r '.defaultBranchRef.name // "main"')

            local asset_id="github-${org}-${repo_name}"

            # Get last commit info
            local last_commit=$(gh api "repos/${org}/${repo_name}/commits/${branch}" --jq '.commit.message' 2>/dev/null | head -1 || echo "")
            local last_author=$(gh api "repos/${org}/${repo_name}/commits/${branch}" --jq '.commit.author.name' 2>/dev/null || echo "")

            # Check for GitHub Actions
            local has_actions=$(gh api "repos/${org}/${repo_name}/actions/workflows" --jq '.total_count > 0' 2>/dev/null || echo "false")

            # Get topics
            local topics=$(gh api "repos/${org}/${repo_name}/topics" --jq '.names | join(",")' 2>/dev/null || echo "")

            # Insert/update asset
            sqlite3 "$INDEX_DB" <<SQL
INSERT OR REPLACE INTO assets (id, type, name, url, status, last_updated, metadata)
VALUES (
    '${asset_id}',
    'github-repo',
    '${repo_name}',
    '${repo_url}',
    'active',
    '${updated_at}',
    '{"org":"${org}","language":"${language}","stars":${stars}}'
);

INSERT OR REPLACE INTO github_repos (id, org, repo, url, description, language, stars, updated_at, last_commit, last_commit_author, branch, has_actions, topics)
VALUES (
    '${asset_id}',
    '${org}',
    '${repo_name}',
    '${repo_url}',
    '${description}',
    '${language}',
    ${stars},
    '${updated_at}',
    '${last_commit}',
    '${last_author}',
    '${branch}',
    ${has_actions},
    '${topics}'
);
SQL

            ((total_repos++))
            echo -e "${GREEN}    ✓${NC} $repo_name"
        done
    done

    echo -e "${GREEN}[INDEX]${NC} Indexed ${total_repos} GitHub repositories"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "github-index" "Indexed ${total_repos} repos across 15 organizations" "coordination,github" 2>/dev/null || true
    fi
}

# Index Cloudflare resources
index_cloudflare() {
    echo -e "${BLUE}[INDEX]${NC} Scanning Cloudflare resources..."

    # Check if wrangler is available
    if ! command -v wrangler &> /dev/null; then
        echo -e "${YELLOW}[INDEX]${NC} Wrangler not found, skipping Cloudflare scan"
        return
    fi

    local total_resources=0

    # Index Pages projects
    echo -e "${CYAN}  Scanning Pages projects...${NC}"
    wrangler pages project list 2>/dev/null | grep -v "Fetching" | tail -n +2 | while read -r line; do
        local project_name=$(echo "$line" | awk '{print $1}')
        local url=$(echo "$line" | awk '{print $2}')

        if [ -n "$project_name" ] && [ "$project_name" != "Fetching" ]; then
            local asset_id="cloudflare-pages-${project_name}"

            sqlite3 "$INDEX_DB" <<SQL
INSERT OR REPLACE INTO assets (id, type, name, url, status, last_updated)
VALUES (
    '${asset_id}',
    'cloudflare-pages',
    '${project_name}',
    '${url}',
    'active',
    datetime('now')
);

INSERT OR REPLACE INTO cloudflare_resources (id, resource_type, name, url, status, deployment_url)
VALUES (
    '${asset_id}',
    'pages',
    '${project_name}',
    '${url}',
    'active',
    '${url}'
);
SQL

            ((total_resources++))
            echo -e "${GREEN}    ✓${NC} $project_name"
        fi
    done

    echo -e "${GREEN}[INDEX]${NC} Indexed ${total_resources} Cloudflare resources"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "cloudflare-index" "Indexed ${total_resources} Cloudflare resources" "coordination,cloudflare" 2>/dev/null || true
    fi
}

# Index Pi services
index_pi_services() {
    echo -e "${BLUE}[INDEX]${NC} Scanning Pi cluster services..."

    local pi_hosts=("192.168.4.38:lucidia" "192.168.4.64:blackroad-pi" "192.168.4.99:lucidia-alt")
    local total_services=0

    for host_info in "${pi_hosts[@]}"; do
        local ip=$(echo "$host_info" | cut -d: -f1)
        local hostname=$(echo "$host_info" | cut -d: -f2)

        echo -e "${CYAN}  Scanning $hostname ($ip)...${NC}"

        # Check if host is reachable
        if timeout 2 nc -z "$ip" 22 2>/dev/null; then
            # Get running services (docker containers)
            local services=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no pi@"$ip" "docker ps --format '{{.Names}}:{{.Ports}}:{{.Status}}'" 2>/dev/null || echo "")

            if [ -n "$services" ]; then
                echo "$services" | while IFS=: read -r service_name ports status; do
                    local asset_id="pi-${hostname}-${service_name}"

                    # Extract port number
                    local port=$(echo "$ports" | grep -oE '[0-9]+' | head -1 || echo "0")

                    sqlite3 "$INDEX_DB" <<SQL
INSERT OR REPLACE INTO assets (id, type, name, status, last_updated, metadata)
VALUES (
    '${asset_id}',
    'pi-service',
    '${service_name}',
    'active',
    datetime('now'),
    '{"hostname":"${hostname}","ip":"${ip}"}'
);

INSERT OR REPLACE INTO pi_services (id, hostname, ip, service_name, port, status, last_checked)
VALUES (
    '${asset_id}',
    '${hostname}',
    '${ip}',
    '${service_name}',
    ${port},
    'active',
    datetime('now')
);
SQL

                    ((total_services++))
                    echo -e "${GREEN}    ✓${NC} $service_name on $hostname"
                done
            fi
        else
            echo -e "${YELLOW}    ! ${hostname} unreachable${NC}"
        fi
    done

    echo -e "${GREEN}[INDEX]${NC} Indexed ${total_services} Pi services"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "pi-index" "Indexed ${total_services} Pi cluster services" "coordination,pi,infrastructure" 2>/dev/null || true
    fi
}

# Search assets
search_assets() {
    local query="$1"

    echo -e "${BLUE}[INDEX]${NC} Searching for: ${query}"
    echo ""

    sqlite3 -column -header "$INDEX_DB" <<EOF
SELECT
    type,
    name,
    status,
    substr(last_updated, 1, 10) as updated,
    substr(url, 1, 50) as url
FROM assets
WHERE name LIKE '%${query}%'
   OR metadata LIKE '%${query}%'
ORDER BY last_updated DESC
LIMIT 20;
EOF
}

# List assets by type
list_assets() {
    local asset_type="$1"

    case "$asset_type" in
        repos|github)
            echo -e "${BLUE}[INDEX]${NC} GitHub Repositories:"
            sqlite3 -column -header "$INDEX_DB" <<EOF
SELECT
    org,
    repo,
    language,
    stars,
    substr(updated_at, 1, 10) as updated
FROM github_repos
ORDER BY updated_at DESC;
EOF
            ;;
        cloudflare|pages)
            echo -e "${BLUE}[INDEX]${NC} Cloudflare Resources:"
            sqlite3 -column -header "$INDEX_DB" <<EOF
SELECT
    resource_type,
    name,
    status,
    deployment_url
FROM cloudflare_resources
ORDER BY name;
EOF
            ;;
        pi|services)
            echo -e "${BLUE}[INDEX]${NC} Pi Cluster Services:"
            sqlite3 -column -header "$INDEX_DB" <<EOF
SELECT
    hostname,
    service_name,
    port,
    status,
    last_checked
FROM pi_services
ORDER BY hostname, service_name;
EOF
            ;;
        *)
            echo -e "${BLUE}[INDEX]${NC} All Assets:"
            sqlite3 -column -header "$INDEX_DB" <<EOF
SELECT
    type,
    COUNT(*) as count,
    COUNT(CASE WHEN status='active' THEN 1 END) as active
FROM assets
GROUP BY type
ORDER BY count DESC;
EOF
            ;;
    esac
}

# Get statistics
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         📊 UNIVERSAL ASSET INDEX STATS 📊             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_assets=$(sqlite3 "$INDEX_DB" "SELECT COUNT(*) FROM assets;")
    local github_repos=$(sqlite3 "$INDEX_DB" "SELECT COUNT(*) FROM github_repos;")
    local cf_resources=$(sqlite3 "$INDEX_DB" "SELECT COUNT(*) FROM cloudflare_resources;")
    local pi_services=$(sqlite3 "$INDEX_DB" "SELECT COUNT(*) FROM pi_services;")
    local last_update=$(sqlite3 "$INDEX_DB" "SELECT MAX(last_updated) FROM assets;")

    echo -e "${GREEN}Total Assets:${NC}           $total_assets"
    echo -e "${GREEN}GitHub Repos:${NC}           $github_repos"
    echo -e "${GREEN}Cloudflare Resources:${NC}   $cf_resources"
    echo -e "${GREEN}Pi Services:${NC}            $pi_services"
    echo -e "${GREEN}Last Updated:${NC}           $last_update"
    echo ""

    echo -e "${BLUE}Asset Breakdown:${NC}"
    list_assets summary
}

# Refresh all indexes
refresh_all() {
    echo -e "${PURPLE}[INDEX]${NC} Refreshing all asset indexes..."
    echo ""

    index_github
    echo ""
    index_cloudflare
    echo ""
    index_pi_services
    echo ""

    show_stats

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "universal-index" "Refreshed all asset indexes: GitHub + Cloudflare + Pi cluster" "coordination,index,refresh" 2>/dev/null || true
    fi
}

# Help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Universal Asset Indexer [INDEX]${NC}

USAGE:
    blackroad-universal-index.sh <command> [options]

COMMANDS:
    init                    Initialize index database
    refresh                 Refresh all asset indexes
    search <query>          Search across all assets
    list <type>             List assets by type
    stats                   Show index statistics
    help                    Show this help

ASSET TYPES:
    repos, github           GitHub repositories
    cloudflare, pages       Cloudflare resources
    pi, services            Pi cluster services
    summary                 All types summary

EXAMPLES:
    # Initialize
    blackroad-universal-index.sh init

    # Refresh everything
    blackroad-universal-index.sh refresh

    # Search
    blackroad-universal-index.sh search "authentication"
    blackroad-universal-index.sh search "api"

    # List by type
    blackroad-universal-index.sh list repos
    blackroad-universal-index.sh list cloudflare
    blackroad-universal-index.sh list pi

    # Stats
    blackroad-universal-index.sh stats

DATABASE: $INDEX_DB
CACHE: $CACHE_DIR
LOG: $LOG_FILE
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_index
            ;;
        refresh)
            refresh_all
            ;;
        search)
            if [ -z "$2" ]; then
                echo -e "${RED}[INDEX]${NC} Error: Search query required"
                exit 1
            fi
            search_assets "$2"
            ;;
        list)
            list_assets "${2:-summary}"
            ;;
        stats)
            show_stats
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[INDEX]${NC} Unknown command: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
