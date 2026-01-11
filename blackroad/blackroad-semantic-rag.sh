#!/usr/bin/env bash
# BlackRoad Semantic RAG - Advanced code understanding across all repos

RAG_DIR="$HOME/.blackroad-rag"
EMBEDDINGS_DIR="$RAG_DIR/embeddings"
CODE_INDEX="$RAG_DIR/code-index.json"
CLONE_DIR="$HOME/blackroad-repos"

mkdir -p "$RAG_DIR" "$EMBEDDINGS_DIR" "$CLONE_DIR"

# GitHub accounts to index
GITHUB_USERS=("blackboxprogramming" "BlackRoad-OS" "BlackRoad-AI" "BlackRoad-Cloud" "BlackRoad-Labs" "BlackRoad-Security" "BlackRoad-Foundation" "BlackRoad-Hardware" "BlackRoad-Interactive" "BlackRoad-Media" "BlackRoad-Studio" "BlackRoad-Ventures" "BlackRoad-Education" "BlackRoad-Archive" "BlackRoad-Gov" "Blackbox-Enterprises")

# Priority repos to clone first
PRIORITY_REPOS=(
    "blackboxprogramming/blackroad-prism-console"
    "blackboxprogramming/blackroad-operating-system"
    "blackboxprogramming/blackroad-os"
    "BlackRoad-OS/blackroad-os-operator"
    "BlackRoad-OS/blackroad-os-prism-enterprise"
    "BlackRoad-OS/blackroad-os-api"
)

echo "============================================================"
echo "🧠 BLACKROAD SEMANTIC RAG SYSTEM"
echo "============================================================"
echo ""

# Step 1: Clone/update priority repos
clone_priority_repos() {
    echo "📥 [1/5] Cloning priority repositories..."
    echo ""
    
    for repo in "${PRIORITY_REPOS[@]}"; do
        REPO_NAME=$(basename "$repo")
        LOCAL_PATH="$CLONE_DIR/$REPO_NAME"
        
        if [ -d "$LOCAL_PATH/.git" ]; then
            echo "  ⬆️  Updating $REPO_NAME..."
            git -C "$LOCAL_PATH" pull --quiet 2>/dev/null || echo "    ⚠️  Update failed (may need access)"
        else
            echo "  ⬇️  Cloning $REPO_NAME..."
            gh repo clone "$repo" "$LOCAL_PATH" --quiet 2>/dev/null || \
                git clone "https://github.com/$repo.git" "$LOCAL_PATH" --quiet 2>/dev/null || \
                echo "    ⚠️  Clone failed (may need access)"
        fi
    done
    
    echo ""
    echo "✅ Priority repos ready"
}

# Step 2: Build comprehensive code index
build_code_index() {
    echo ""
    echo "🔍 [2/5] Building comprehensive code index..."
    echo ""
    
    > "$CODE_INDEX"
    echo "{\"repos\": [" > "$CODE_INDEX"
    
    FIRST=true
    for dir in "$CLONE_DIR"/*; do
        if [ -d "$dir/.git" ]; then
            REPO_NAME=$(basename "$dir")
            echo "  → Indexing $REPO_NAME..."
            
            # Extract repo metadata
            REMOTE=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "unknown")
            BRANCH=$(git -C "$dir" branch --show-current 2>/dev/null || echo "main")
            LAST_COMMIT=$(git -C "$dir" log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "unknown")
            
            # Count files by type
            TOTAL_FILES=$(find "$dir" -type f ! -path "*/\.*" | wc -l | tr -d ' ')
            PY_FILES=$(find "$dir" -name "*.py" | wc -l | tr -d ' ')
            JS_FILES=$(find "$dir" -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" | wc -l | tr -d ' ')
            HTML_FILES=$(find "$dir" -name "*.html" | wc -l | tr -d ' ')
            
            # Find key files
            README=$(find "$dir" -maxdepth 2 -iname "README*" -type f | head -1)
            PACKAGE_JSON=$(find "$dir" -maxdepth 2 -name "package.json" -type f | head -1)
            REQUIREMENTS=$(find "$dir" -maxdepth 2 -name "requirements.txt" -type f | head -1)
            
            # Build JSON entry
            if [ "$FIRST" = false ]; then
                echo "," >> "$CODE_INDEX"
            fi
            FIRST=false
            
            cat >> "$CODE_INDEX" << REPOENTRY
  {
    "name": "$REPO_NAME",
    "path": "$dir",
    "remote": "$REMOTE",
    "branch": "$BRANCH",
    "last_commit": "$LAST_COMMIT",
    "stats": {
      "total_files": $TOTAL_FILES,
      "python_files": $PY_FILES,
      "javascript_files": $JS_FILES,
      "html_files": $HTML_FILES
    },
    "key_files": {
      "readme": "$([ -n "$README" ] && echo "$README" || echo "null")",
      "package_json": "$([ -n "$PACKAGE_JSON" ] && echo "$PACKAGE_JSON" || echo "null")",
      "requirements": "$([ -n "$REQUIREMENTS" ] && echo "$REQUIREMENTS" || echo "null")"
    }
  }
REPOENTRY
        fi
    done
    
    echo "" >> "$CODE_INDEX"
    echo "]}" >> "$CODE_INDEX"
    
    INDEXED_COUNT=$(jq '.repos | length' "$CODE_INDEX" 2>/dev/null || echo "0")
    echo ""
    echo "✅ Indexed $INDEXED_COUNT repositories"
}

# Step 3: Extract semantic chunks
extract_semantic_chunks() {
    echo ""
    echo "📝 [3/5] Extracting semantic code chunks..."
    echo ""
    
    CHUNKS_FILE="$RAG_DIR/code-chunks.jsonl"
    > "$CHUNKS_FILE"
    
    # Extract from Python files
    echo "  → Processing Python files..."
    find "$CLONE_DIR" -name "*.py" ! -path "*/\.*" -type f | while read -r file; do
        REPO=$(echo "$file" | sed "s|$CLONE_DIR/||" | cut -d'/' -f1)
        REL_PATH=$(echo "$file" | sed "s|$CLONE_DIR/$REPO/||")
        
        # Extract functions and classes
        grep -n "^def \|^class " "$file" 2>/dev/null | while IFS=: read -r line_num content; do
            # Get surrounding context (10 lines)
            CHUNK=$(sed -n "$((line_num-2)),$((line_num+8))p" "$file" 2>/dev/null)
            
            echo "{\"repo\": \"$REPO\", \"file\": \"$REL_PATH\", \"line\": $line_num, \"type\": \"python\", \"content\": $(echo "$CHUNK" | jq -Rs .)}" >> "$CHUNKS_FILE"
        done
    done
    
    # Extract from JavaScript/TypeScript
    echo "  → Processing JavaScript/TypeScript files..."
    find "$CLONE_DIR" -name "*.js" -o -name "*.ts" ! -path "*/\.*" -type f | while read -r file; do
        REPO=$(echo "$file" | sed "s|$CLONE_DIR/||" | cut -d'/' -f1)
        REL_PATH=$(echo "$file" | sed "s|$CLONE_DIR/$REPO/||")
        
        # Extract functions and exports
        grep -n "^export \|^function \|^const.*=.*=>\\|^class " "$file" 2>/dev/null | while IFS=: read -r line_num content; do
            CHUNK=$(sed -n "$((line_num-2)),$((line_num+8))p" "$file" 2>/dev/null)
            
            echo "{\"repo\": \"$REPO\", \"file\": \"$REL_PATH\", \"line\": $line_num, \"type\": \"javascript\", \"content\": $(echo "$CHUNK" | jq -Rs .)}" >> "$CHUNKS_FILE"
        done
    done
    
    CHUNK_COUNT=$(wc -l < "$CHUNKS_FILE" | tr -d ' ')
    echo ""
    echo "✅ Extracted $CHUNK_COUNT semantic chunks"
}

# Step 4: Build searchable keyword index
build_keyword_index() {
    echo ""
    echo "🔎 [4/5] Building keyword search index..."
    echo ""
    
    KEYWORDS_FILE="$RAG_DIR/keywords.txt"
    > "$KEYWORDS_FILE"
    
    # Extract unique keywords from code
    echo "  → Extracting identifiers..."
    find "$CLONE_DIR" -name "*.py" -o -name "*.js" -o -name "*.ts" ! -path "*/\.*" -type f | \
        xargs grep -oh "\b[a-zA-Z_][a-zA-Z0-9_]*\b" 2>/dev/null | \
        sort -u > "$KEYWORDS_FILE"
    
    KEYWORD_COUNT=$(wc -l < "$KEYWORDS_FILE" | tr -d ' ')
    echo ""
    echo "✅ Built index with $KEYWORD_COUNT unique keywords"
}

# Step 5: Generate search capabilities
generate_search_tools() {
    echo ""
    echo "🛠️  [5/5] Generating search tools..."
    echo ""
    
    # Create semantic search script
    cat > "$RAG_DIR/semantic-search.sh" << 'SEARCH'
#!/usr/bin/env bash
QUERY="$1"
RAG_DIR="$HOME/.blackroad-rag"

if [ -z "$QUERY" ]; then
    echo "Usage: $0 <search query>"
    exit 1
fi

echo "🔍 Semantic Search: $QUERY"
echo ""

# Search in code chunks
echo "=== Code Matches ==="
grep -i "$QUERY" "$RAG_DIR/code-chunks.jsonl" | jq -r '"\(.repo)/\(.file):\(.line) - \(.content[:100])"' | head -20

echo ""
echo "=== Repository Matches ==="
jq -r ".repos[] | select(.name | ascii_downcase | contains(\"${QUERY,,}\")) | \"[\(.name)] \(.path)\"" "$RAG_DIR/code-index.json"
SEARCH
    
    chmod +x "$RAG_DIR/semantic-search.sh"
    
    # Create function finder
    cat > "$RAG_DIR/find-function.sh" << 'FUNCFIND'
#!/usr/bin/env bash
FUNC_NAME="$1"
RAG_DIR="$HOME/.blackroad-rag"

echo "🔍 Finding function: $FUNC_NAME"
echo ""

grep -i "def $FUNC_NAME\|function $FUNC_NAME\|const $FUNC_NAME" "$RAG_DIR/code-chunks.jsonl" | \
    jq -r '"\(.repo)/\(.file):\(.line)\n\(.content)\n"'
FUNCFIND
    
    chmod +x "$RAG_DIR/find-function.sh"
    
    echo "✅ Search tools created:"
    echo "  • $RAG_DIR/semantic-search.sh <query>"
    echo "  • $RAG_DIR/find-function.sh <function_name>"
}

# Main execution
case "$1" in
    init)
        clone_priority_repos
        build_code_index
        extract_semantic_chunks
        build_keyword_index
        generate_search_tools
        
        echo ""
        echo "============================================================"
        echo "✅ SEMANTIC RAG SYSTEM READY!"
        echo "============================================================"
        echo ""
        echo "📊 Statistics:"
        jq -r '"  Repos indexed: " + (.repos | length | tostring)' "$CODE_INDEX"
        echo "  Code chunks: $(wc -l < "$RAG_DIR/code-chunks.jsonl" | tr -d ' ')"
        echo "  Keywords: $(wc -l < "$RAG_DIR/keywords.txt" | tr -d ' ')"
        echo ""
        echo "🔍 Search commands:"
        echo "  $RAG_DIR/semantic-search.sh 'hailo ai'"
        echo "  $RAG_DIR/find-function.sh 'memory_system'"
        echo "  ~/blackroad-semantic-rag.sh search <query>"
        ;;
    
    search)
        shift
        "$RAG_DIR/semantic-search.sh" "$*"
        ;;
    
    function)
        shift
        "$RAG_DIR/find-function.sh" "$*"
        ;;
    
    stats)
        echo "📊 BlackRoad Semantic RAG Statistics"
        echo "===================================="
        jq -r '"Repos: " + (.repos | length | tostring)' "$CODE_INDEX"
        echo "Chunks: $(wc -l < "$RAG_DIR/code-chunks.jsonl" 2>/dev/null | tr -d ' ')"
        echo "Keywords: $(wc -l < "$RAG_DIR/keywords.txt" 2>/dev/null | tr -d ' ')"
        echo ""
        echo "Top repos by file count:"
        jq -r '.repos | sort_by(.stats.total_files) | reverse | .[0:5] | .[] | "  \(.name): \(.stats.total_files) files"' "$CODE_INDEX"
        ;;
    
    *)
        echo "BlackRoad Semantic RAG System"
        echo ""
        echo "Usage:"
        echo "  $0 init                - Build complete semantic index"
        echo "  $0 search <query>      - Semantic search across all repos"
        echo "  $0 function <name>     - Find function definition"
        echo "  $0 stats               - Show indexing statistics"
        echo ""
        echo "Examples:"
        echo "  $0 init"
        echo "  $0 search 'authentication system'"
        echo "  $0 function 'process_payment'"
        ;;
esac
