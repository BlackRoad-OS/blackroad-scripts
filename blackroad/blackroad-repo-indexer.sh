#!/usr/bin/env bash
# BlackRoad Repo Indexer - Fast search across all repositories

INDEX_DIR="$HOME/.blackroad-repo-index"
CACHE_FILE="$INDEX_DIR/repo-cache.db"
METADATA_FILE="$INDEX_DIR/metadata.json"

mkdir -p "$INDEX_DIR"

# Initialize or update index
init_index() {
    echo "🔍 Initializing BlackRoad Repository Index..."
    
    # Get all repos from all orgs
    ORGS=(
        "BlackRoad-AI"
        "BlackRoad-Archive"
        "BlackRoad-Cloud"
        "BlackRoad-Education"
        "BlackRoad-Foundation"
        "BlackRoad-Gov"
        "BlackRoad-Hardware"
        "BlackRoad-Interactive"
        "BlackRoad-Labs"
        "BlackRoad-Media"
        "BlackRoad-OS"
        "BlackRoad-Security"
        "BlackRoad-Studio"
        "BlackRoad-Ventures"
        "Blackbox-Enterprises"
    )
    
    echo "{\"repos\": [], \"updated\": \"$(date -Iseconds)\"}" > "$METADATA_FILE"
    > "$CACHE_FILE"
    
    for org in "${ORGS[@]}"; do
        echo "  → Indexing $org..."
        gh repo list "$org" --limit 1000 --json name,url,description,updatedAt,primaryLanguage \
            >> "$CACHE_FILE" 2>/dev/null || echo "    (skipped - no access)"
    done
    
    # Count repos
    REPO_COUNT=$(cat "$CACHE_FILE" | jq -s 'add | length' 2>/dev/null || echo "0")
    echo "✅ Indexed $REPO_COUNT repositories"
    
    # Update metadata
    jq ".repos = $(cat "$CACHE_FILE" | jq -s 'add') | .count = $REPO_COUNT" "$METADATA_FILE" > "$METADATA_FILE.tmp"
    mv "$METADATA_FILE.tmp" "$METADATA_FILE"
}

# Fast search across repos
search_repos() {
    QUERY="$1"
    QUERY_LOWER=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')
    
    if [ ! -f "$METADATA_FILE" ]; then
        echo "❌ Index not found. Run: ~/blackroad-repo-indexer.sh init"
        return 1
    fi
    
    echo "🔍 Searching for: $QUERY"
    echo ""
    
    # Search in repo names, descriptions, and languages
    jq -r --arg query "$QUERY_LOWER" '.repos[] | select(
        (.name | ascii_downcase | contains($query)) or
        (.description // "" | ascii_downcase | contains($query)) or
        (.primaryLanguage.name // "" | ascii_downcase | contains($query))
    ) | "[\(.name)] \(.url)\n  \(.description // "No description")\n  Language: \(.primaryLanguage.name // "Unknown") | Updated: \(.updatedAt)\n"' \
        "$METADATA_FILE" | head -40
}

# Search file contents across repos (using GitHub API)
search_code() {
    QUERY="$1"
    ORG="${2:-BlackRoad-OS}"
    
    echo "🔍 Searching code for: $QUERY in $ORG"
    echo ""
    
    gh search code "$QUERY" --owner "$ORG" --limit 20 \
        --json repository,path,url \
        --jq '.[] | "[\(.repository.name)] \(.path)\n  \(.url)\n"'
}

# Clone or update repo for local search
clone_or_update() {
    REPO_URL="$1"
    REPO_NAME=$(basename "$REPO_URL" .git)
    LOCAL_PATH="$HOME/blackroad-repos/$REPO_NAME"
    
    if [ -d "$LOCAL_PATH" ]; then
        echo "⬆️  Updating $REPO_NAME..."
        git -C "$LOCAL_PATH" pull --quiet
    else
        echo "⬇️  Cloning $REPO_NAME..."
        mkdir -p "$HOME/blackroad-repos"
        gh repo clone "$REPO_URL" "$LOCAL_PATH" --quiet
    fi
    
    echo "$LOCAL_PATH"
}

# Fast grep across locally cloned repos
fast_grep() {
    PATTERN="$1"
    REPOS_DIR="$HOME/blackroad-repos"
    
    if [ ! -d "$REPOS_DIR" ]; then
        echo "❌ No local repos found. Clone some first with: clone_or_update"
        return 1
    fi
    
    echo "🔍 Fast grep for: $PATTERN"
    echo ""
    
    # Use ripgrep if available, fallback to grep
    if command -v rg &> /dev/null; then
        rg --type-add 'doc:*.md' --type-add 'config:*.{json,yaml,yml,toml}' \
            -i "$PATTERN" "$REPOS_DIR" \
            --heading --line-number --color=always | head -100
    else
        grep -r -i --color=always "$PATTERN" "$REPOS_DIR" | head -100
    fi
}

# Show stats
stats() {
    if [ ! -f "$METADATA_FILE" ]; then
        echo "❌ Index not found. Run: ~/blackroad-repo-indexer.sh init"
        return 1
    fi
    
    echo "📊 BlackRoad Repository Index Stats"
    echo "===================================="
    
    TOTAL=$(jq -r '.count' "$METADATA_FILE")
    UPDATED=$(jq -r '.updated' "$METADATA_FILE")
    
    echo "Total repos: $TOTAL"
    echo "Last updated: $UPDATED"
    echo ""
    
    echo "Top languages:"
    jq -r '.repos[].primaryLanguage.name // "Unknown"' "$METADATA_FILE" \
        | sort | uniq -c | sort -rn | head -10
    
    echo ""
    echo "Most recently updated:"
    jq -r '.repos | sort_by(.updatedAt) | reverse | .[0:5] | .[] | "  \(.name) - \(.updatedAt)"' "$METADATA_FILE"
}

# Main command dispatcher
case "$1" in
    init)
        init_index
        ;;
    search)
        search_repos "$2"
        ;;
    code)
        search_code "$2" "$3"
        ;;
    grep)
        fast_grep "$2"
        ;;
    clone)
        clone_or_update "$2"
        ;;
    stats)
        stats
        ;;
    *)
        echo "BlackRoad Repository Indexer"
        echo ""
        echo "Usage:"
        echo "  $0 init              - Build/update repository index"
        echo "  $0 search <query>    - Search repo names/descriptions"
        echo "  $0 code <query> [org] - Search code via GitHub API"
        echo "  $0 grep <pattern>    - Fast grep across local repos"
        echo "  $0 clone <url>       - Clone or update repo locally"
        echo "  $0 stats             - Show index statistics"
        echo ""
        echo "Examples:"
        echo "  $0 init"
        echo "  $0 search hailo"
        echo "  $0 code 'memory-system' BlackRoad-OS"
        echo "  $0 grep 'Hailo-8'"
        ;;
esac
