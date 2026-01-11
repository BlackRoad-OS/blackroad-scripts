#!/bin/bash
# [SEMANTIC] - BlackRoad Semantic Memory Search
# Natural language search across all memory and code
# Version: 1.0.0

set -e

SEMANTIC_DIR="$HOME/.blackroad/semantic"
SEMANTIC_DB="$SEMANTIC_DIR/vectors.db"
CACHE_DIR="$SEMANTIC_DIR/cache"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize semantic search
init_semantic() {
    echo -e "${BLUE}[SEMANTIC]${NC} Initializing semantic memory search..."

    mkdir -p "$SEMANTIC_DIR" "$CACHE_DIR"

    # Create database for semantic embeddings
    sqlite3 "$SEMANTIC_DB" <<EOF
CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    content TEXT NOT NULL,
    summary TEXT,
    timestamp TEXT,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS embeddings (
    id TEXT PRIMARY KEY,
    document_id TEXT NOT NULL,
    embedding_vector TEXT NOT NULL,
    model TEXT DEFAULT 'simple-hash',
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents(id)
);

CREATE TABLE IF NOT EXISTS topics (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    document_ids TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS search_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    results_count INTEGER,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_documents_source ON documents(source);
CREATE INDEX IF NOT EXISTS idx_documents_timestamp ON documents(timestamp);
CREATE INDEX IF NOT EXISTS idx_embeddings_doc ON embeddings(document_id);
EOF

    echo -e "${GREEN}[SEMANTIC]${NC} Semantic search initialized at: $SEMANTIC_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "semantic-search" "Initialized [SEMANTIC] system for natural language search" "coordination,semantic" 2>/dev/null || true
    fi
}

# Index memory journal for semantic search
index_memory() {
    echo -e "${BLUE}[SEMANTIC]${NC} Indexing memory journal..."

    local journal="$HOME/.blackroad/memory/journals/master-journal.jsonl"

    if [ ! -f "$journal" ]; then
        echo -e "${RED}[SEMANTIC]${NC} Memory journal not found"
        return 1
    fi

    local count=0

    # Read and index each memory entry
    while IFS= read -r line; do
        local timestamp=$(echo "$line" | jq -r '.timestamp')
        local action=$(echo "$line" | jq -r '.action')
        local entity=$(echo "$line" | jq -r '.entity')
        local details=$(echo "$line" | jq -r '.details')
        local sha=$(echo "$line" | jq -r '.sha256')

        local doc_id="memory-${sha:0:16}"
        local content="${action}: ${entity} - ${details}"
        local summary="${action} on ${entity}"

        # Simple keyword-based embedding (hash of important terms)
        local keywords="${action} ${entity} ${details}"
        local embedding=$(echo -n "$keywords" | shasum -a 256 | cut -d' ' -f1)

        # Insert document
        sqlite3 "$SEMANTIC_DB" <<SQL
INSERT OR REPLACE INTO documents (id, source, content, summary, timestamp, metadata)
VALUES (
    '${doc_id}',
    'memory-journal',
    '${content}',
    '${summary}',
    '${timestamp}',
    '{"action":"${action}","entity":"${entity}"}'
);

INSERT OR REPLACE INTO embeddings (id, document_id, embedding_vector)
VALUES (
    'emb-${doc_id}',
    '${doc_id}',
    '${embedding}'
);
SQL

        ((count++))

        # Progress indicator
        if [ $((count % 100)) -eq 0 ]; then
            echo -e "${CYAN}  Indexed $count entries...${NC}"
        fi
    done < "$journal"

    echo -e "${GREEN}[SEMANTIC]${NC} Indexed $count memory entries"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "semantic-index" "Indexed $count memory entries for semantic search" "coordination,semantic,indexing" 2>/dev/null || true
    fi
}

# Index code repositories
index_code() {
    echo -e "${BLUE}[SEMANTIC]${NC} Indexing code repositories..."

    local projects_dir="$HOME/projects"

    if [ ! -d "$projects_dir" ]; then
        echo -e "${YELLOW}[SEMANTIC]${NC} Projects directory not found"
        return 0
    fi

    local count=0

    # Find all code files
    find "$projects_dir" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | while read -r file; do
        local repo_name=$(echo "$file" | sed 's|.*/projects/||' | cut -d/ -f1)
        local file_name=$(basename "$file")
        local doc_id="code-$(echo "$file" | shasum -a 256 | cut -d' ' -f1 | cut -c1-16)"

        # Read first 500 chars of file for indexing
        local content=$(head -c 500 "$file" 2>/dev/null | tr '\n' ' ')
        local summary="Code: $file_name in $repo_name"

        # Extract keywords from file
        local keywords=$(grep -oE '[A-Za-z_][A-Za-z0-9_]{3,}' "$file" 2>/dev/null | head -20 | tr '\n' ' ')
        local embedding=$(echo -n "$keywords" | shasum -a 256 | cut -d' ' -f1)

        # Insert document
        sqlite3 "$SEMANTIC_DB" <<SQL 2>/dev/null
INSERT OR REPLACE INTO documents (id, source, content, summary, metadata)
VALUES (
    '${doc_id}',
    'code',
    '${content}',
    '${summary}',
    '{"repo":"${repo_name}","file":"${file_name}","path":"${file}"}'
);

INSERT OR REPLACE INTO embeddings (id, document_id, embedding_vector)
VALUES (
    'emb-${doc_id}',
    '${doc_id}',
    '${embedding}'
);
SQL

        ((count++))

        if [ $((count % 50)) -eq 0 ]; then
            echo -e "${CYAN}  Indexed $count code files...${NC}"
        fi

        # Limit to prevent excessive indexing on first run
        if [ $count -ge 500 ]; then
            echo -e "${YELLOW}  Limiting to 500 files for initial index${NC}"
            break
        fi
    done

    echo -e "${GREEN}[SEMANTIC]${NC} Indexed $count code files"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "semantic-code-index" "Indexed $count code files for semantic search" "coordination,semantic,code" 2>/dev/null || true
    fi
}

# Semantic search
search() {
    local query="$1"

    if [ -z "$query" ]; then
        echo -e "${RED}[SEMANTIC]${NC} Query required"
        return 1
    fi

    echo -e "${BLUE}[SEMANTIC]${NC} Searching for: \"${query}\""
    echo ""

    # Simple keyword-based search (could be enhanced with actual embeddings)
    local search_terms=$(echo "$query" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '\n' | grep -v '^$')

    # Build search pattern
    local pattern=""
    for term in $search_terms; do
        pattern="${pattern}%${term}%"
    done

    # Log search
    sqlite3 "$SEMANTIC_DB" "INSERT INTO search_history (query) VALUES ('${query}');" 2>/dev/null || true

    # Search documents
    echo -e "${YELLOW}Results from Memory:${NC}"
    sqlite3 -column "$SEMANTIC_DB" <<EOF
SELECT
    substr(summary, 1, 60) as summary,
    substr(timestamp, 1, 10) as date
FROM documents
WHERE source = 'memory-journal'
  AND (LOWER(content) LIKE LOWER('%${query}%')
    OR LOWER(summary) LIKE LOWER('%${query}%'))
ORDER BY timestamp DESC
LIMIT 10;
EOF

    echo ""
    echo -e "${YELLOW}Results from Code:${NC}"
    sqlite3 -column "$SEMANTIC_DB" <<EOF
SELECT
    substr(summary, 1, 70) as file,
    'code' as type
FROM documents
WHERE source = 'code'
  AND (LOWER(content) LIKE LOWER('%${query}%')
    OR LOWER(summary) LIKE LOWER('%${query}%')
    OR LOWER(metadata) LIKE LOWER('%${query}%'))
LIMIT 10;
EOF

    echo ""
    local results=$(sqlite3 "$SEMANTIC_DB" "SELECT COUNT(*) FROM documents WHERE LOWER(content) LIKE LOWER('%${query}%');")
    echo -e "${GREEN}[SEMANTIC]${NC} Found $results total matches"
}

# Find similar documents
similar() {
    local doc_id="$1"

    echo -e "${BLUE}[SEMANTIC]${NC} Finding similar documents to: ${doc_id}"
    echo ""

    # Get the embedding for this document
    local embedding=$(sqlite3 "$SEMANTIC_DB" "SELECT embedding_vector FROM embeddings WHERE document_id = '${doc_id}';")

    if [ -z "$embedding" ]; then
        echo -e "${RED}[SEMANTIC]${NC} Document not found"
        return 1
    fi

    # Find documents with similar embeddings (simplified - uses same source for now)
    sqlite3 -column -header "$SEMANTIC_DB" <<EOF
SELECT
    d.summary,
    d.source,
    substr(d.timestamp, 1, 10) as date
FROM documents d
JOIN embeddings e ON d.id = e.document_id
WHERE d.source = (SELECT source FROM documents WHERE id = '${doc_id}')
  AND d.id != '${doc_id}'
ORDER BY d.timestamp DESC
LIMIT 10;
EOF
}

# Summarize topic
summarize() {
    local topic="$1"
    local timeframe="${2:-all}"

    echo -e "${BLUE}[SEMANTIC]${NC} Summarizing: ${topic} (timeframe: ${timeframe})"
    echo ""

    local time_filter=""
    case "$timeframe" in
        today)
            time_filter="AND timestamp >= date('now')"
            ;;
        week|last-week)
            time_filter="AND timestamp >= date('now', '-7 days')"
            ;;
        month|last-month)
            time_filter="AND timestamp >= date('now', '-30 days')"
            ;;
    esac

    # Get all related documents
    local docs=$(sqlite3 "$SEMANTIC_DB" "
        SELECT content
        FROM documents
        WHERE LOWER(content) LIKE LOWER('%${topic}%')
        $time_filter
        ORDER BY timestamp DESC;
    ")

    local count=$(echo "$docs" | wc -l)

    echo -e "${YELLOW}Summary for: ${topic}${NC}"
    echo ""
    echo "Found $count related documents"
    echo ""

    # Show top actions
    echo -e "${CYAN}Most common actions:${NC}"
    sqlite3 "$SEMANTIC_DB" <<EOF
SELECT
    json_extract(metadata, '$.action') as action,
    COUNT(*) as count
FROM documents
WHERE LOWER(content) LIKE LOWER('%${topic}%')
  AND source = 'memory-journal'
  $time_filter
GROUP BY action
ORDER BY count DESC
LIMIT 5;
EOF

    echo ""
    echo -e "${CYAN}Recent activity:${NC}"
    sqlite3 -column "$SEMANTIC_DB" <<EOF
SELECT
    substr(timestamp, 1, 10) as date,
    substr(summary, 1, 60) as what_happened
FROM documents
WHERE LOWER(content) LIKE LOWER('%${topic}%')
  $time_filter
ORDER BY timestamp DESC
LIMIT 5;
EOF
}

# Get statistics
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      🔍 SEMANTIC SEARCH STATISTICS 🔍                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_docs=$(sqlite3 "$SEMANTIC_DB" "SELECT COUNT(*) FROM documents;")
    local memory_docs=$(sqlite3 "$SEMANTIC_DB" "SELECT COUNT(*) FROM documents WHERE source='memory-journal';")
    local code_docs=$(sqlite3 "$SEMANTIC_DB" "SELECT COUNT(*) FROM documents WHERE source='code';")
    local total_searches=$(sqlite3 "$SEMANTIC_DB" "SELECT COUNT(*) FROM search_history;")

    echo -e "${GREEN}Total Documents:${NC}      $total_docs"
    echo -e "${GREEN}Memory Entries:${NC}       $memory_docs"
    echo -e "${GREEN}Code Files:${NC}           $code_docs"
    echo -e "${GREEN}Total Searches:${NC}       $total_searches"
    echo ""

    echo -e "${BLUE}Recent Searches:${NC}"
    sqlite3 -column "$SEMANTIC_DB" <<EOF
SELECT
    query,
    substr(timestamp, 1, 16) as when
FROM search_history
ORDER BY timestamp DESC
LIMIT 5;
EOF

    echo ""
    echo -e "${BLUE}Most Common Topics:${NC}"
    sqlite3 "$SEMANTIC_DB" <<EOF
SELECT
    json_extract(metadata, '$.action') as topic,
    COUNT(*) as count
FROM documents
WHERE source = 'memory-journal'
GROUP BY topic
ORDER BY count DESC
LIMIT 5;
EOF
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Semantic Memory Search [SEMANTIC]${NC}

USAGE:
    blackroad-semantic-memory.sh <command> [options]

COMMANDS:
    init                        Initialize semantic search
    index-memory                Index memory journal
    index-code                  Index code repositories
    search <query>              Semantic search
    similar <doc-id>            Find similar documents
    summarize <topic> [time]    Summarize topic activity
    stats                       Show statistics
    help                        Show this help

EXAMPLES:
    # Initialize
    blackroad-semantic-memory.sh init

    # Index everything
    blackroad-semantic-memory.sh index-memory
    blackroad-semantic-memory.sh index-code

    # Search
    blackroad-semantic-memory.sh search "authentication implementation"
    blackroad-semantic-memory.sh search "how did we handle rate limiting"
    blackroad-semantic-memory.sh search "cloudflare deployment"

    # Summarize
    blackroad-semantic-memory.sh summarize "api" last-week
    blackroad-semantic-memory.sh summarize "deployment" today

    # Stats
    blackroad-semantic-memory.sh stats

TIMEFRAMES:
    today, week, last-week, month, last-month, all (default)

DATABASE: $SEMANTIC_DB
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_semantic
            ;;
        index-memory)
            index_memory
            ;;
        index-code)
            index_code
            ;;
        search)
            if [ -z "$2" ]; then
                echo -e "${RED}[SEMANTIC]${NC} Search query required"
                exit 1
            fi
            search "$2"
            ;;
        similar)
            if [ -z "$2" ]; then
                echo -e "${RED}[SEMANTIC]${NC} Document ID required"
                exit 1
            fi
            similar "$2"
            ;;
        summarize)
            if [ -z "$2" ]; then
                echo -e "${RED}[SEMANTIC]${NC} Topic required"
                exit 1
            fi
            summarize "$2" "${3:-all}"
            ;;
        stats)
            show_stats
            ;;
        status)
            if [ -f "$SEMANTIC_DB" ]; then
                echo -e "${GREEN}[SEMANTIC]${NC} Ready"
                show_stats
            else
                echo -e "${YELLOW}[SEMANTIC]${NC} Not initialized (run: init)"
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[SEMANTIC]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
