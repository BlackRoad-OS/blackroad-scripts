#!/bin/bash
# [GRAPH] - BlackRoad Knowledge Graph System
# Maps relationships between ALL components
# Version: 1.0.0

set -e

GRAPH_DIR="$HOME/.blackroad/graph"
GRAPH_DB="$GRAPH_DIR/knowledge.db"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize graph database
init_graph() {
    echo -e "${BLUE}[GRAPH]${NC} Initializing Knowledge Graph..."

    mkdir -p "$GRAPH_DIR"

    # Create SQLite database with graph structure
    sqlite3 "$GRAPH_DB" <<EOF
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS edges (
    id TEXT PRIMARY KEY,
    from_node TEXT NOT NULL,
    to_node TEXT NOT NULL,
    relationship TEXT NOT NULL,
    strength REAL DEFAULT 1.0,
    metadata TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (from_node) REFERENCES nodes(id),
    FOREIGN KEY (to_node) REFERENCES nodes(id)
);

CREATE TABLE IF NOT EXISTS dependencies (
    id TEXT PRIMARY KEY,
    component_id TEXT NOT NULL,
    depends_on TEXT NOT NULL,
    dependency_type TEXT,
    required BOOLEAN DEFAULT 1,
    FOREIGN KEY (id) REFERENCES edges(id)
);

CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);
CREATE INDEX IF NOT EXISTS idx_edges_from ON edges(from_node);
CREATE INDEX IF NOT EXISTS idx_edges_to ON edges(to_node);
CREATE INDEX IF NOT EXISTS idx_edges_relationship ON edges(relationship);
EOF

    echo -e "${GREEN}[GRAPH]${NC} Knowledge graph initialized at: $GRAPH_DB"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log created "knowledge-graph" "Initialized [GRAPH] system at $GRAPH_DB" "coordination,graph" 2>/dev/null || true
    fi
}

# Add node
add_node() {
    local node_id="$1"
    local node_type="$2"
    local node_name="$3"
    local metadata="${4:-{}}"

    sqlite3 "$GRAPH_DB" <<EOF
INSERT OR REPLACE INTO nodes (id, type, name, metadata)
VALUES ('${node_id}', '${node_type}', '${node_name}', '${metadata}');
EOF

    echo -e "${GREEN}[GRAPH]${NC} Added node: $node_name ($node_type)"
}

# Add edge
add_edge() {
    local from_node="$1"
    local to_node="$2"
    local relationship="$3"
    local strength="${4:-1.0}"

    local edge_id="${from_node}-${relationship}-${to_node}"

    sqlite3 "$GRAPH_DB" <<EOF
INSERT OR REPLACE INTO edges (id, from_node, to_node, relationship, strength)
VALUES ('${edge_id}', '${from_node}', '${to_node}', '${relationship}', ${strength});
EOF

    echo -e "${GREEN}[GRAPH]${NC} Added edge: $from_node --[$relationship]--> $to_node"
}

# Query: What depends on this?
depends_on() {
    local component="$1"

    echo -e "${BLUE}[GRAPH]${NC} Components that depend on: ${component}"
    echo ""

    sqlite3 -column -header "$GRAPH_DB" <<EOF
SELECT
    n.name as dependent,
    n.type,
    e.relationship,
    e.strength
FROM edges e
JOIN nodes n ON e.from_node = n.id
WHERE e.to_node LIKE '%${component}%'
   OR (SELECT name FROM nodes WHERE id = e.to_node) LIKE '%${component}%'
ORDER BY e.strength DESC;
EOF
}

# Query: What does this depend on?
required_by() {
    local component="$1"

    echo -e "${BLUE}[GRAPH]${NC} Dependencies required by: ${component}"
    echo ""

    sqlite3 -column -header "$GRAPH_DB" <<EOF
SELECT
    n.name as dependency,
    n.type,
    e.relationship,
    e.strength
FROM edges e
JOIN nodes n ON e.to_node = n.id
WHERE e.from_node LIKE '%${component}%'
   OR (SELECT name FROM nodes WHERE id = e.from_node) LIKE '%${component}%'
ORDER BY e.strength DESC;
EOF
}

# Query: Impact analysis
impacts() {
    local component="$1"

    echo -e "${BLUE}[GRAPH]${NC} Impact Analysis: What breaks if we change ${component}?"
    echo ""

    # Direct dependencies
    echo -e "${YELLOW}Direct Impact:${NC}"
    sqlite3 -column "$GRAPH_DB" <<EOF
SELECT DISTINCT '  → ' || n.name || ' (' || n.type || ')'
FROM edges e
JOIN nodes n ON e.from_node = n.id
WHERE e.to_node LIKE '%${component}%'
   OR (SELECT name FROM nodes WHERE id = e.to_node) LIKE '%${component}%';
EOF

    echo ""
    echo -e "${YELLOW}Indirect Impact (2nd degree):${NC}"

    # 2nd degree dependencies
    sqlite3 -column "$GRAPH_DB" <<EOF
SELECT DISTINCT '  → ' || n2.name || ' (' || n2.type || ')'
FROM edges e1
JOIN edges e2 ON e1.from_node = e2.to_node
JOIN nodes n2 ON e2.from_node = n2.id
WHERE e1.to_node LIKE '%${component}%'
   OR (SELECT name FROM nodes WHERE id = e1.to_node) LIKE '%${component}%';
EOF
}

# Query: Connected components
connected_to() {
    local component="$1"

    echo -e "${BLUE}[GRAPH]${NC} All components connected to: ${component}"
    echo ""

    sqlite3 -column -header "$GRAPH_DB" <<EOF
SELECT DISTINCT
    n.name,
    n.type,
    CASE
        WHEN e.from_node = (SELECT id FROM nodes WHERE name LIKE '%${component}%' LIMIT 1)
        THEN '→ uses'
        ELSE '← used by'
    END as direction
FROM edges e
JOIN nodes n ON (n.id = e.from_node OR n.id = e.to_node)
WHERE e.from_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
   OR e.to_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
ORDER BY direction, n.name;
EOF
}

# Build graph from codebase
build_from_code() {
    echo -e "${BLUE}[GRAPH]${NC} Building knowledge graph from codebase..."

    # This would scan repos and extract:
    # - Import statements (dependencies)
    # - API calls (service dependencies)
    # - Database queries (data dependencies)
    # - Environment variables (config dependencies)

    echo -e "${YELLOW}[GRAPH]${NC} Scanning for dependencies..."

    # Example: Scan Python imports
    if [ -d ~/projects ]; then
        find ~/projects -name "*.py" -type f 2>/dev/null | while read -r file; do
            local repo_name=$(echo "$file" | sed 's|.*/projects/||' | cut -d/ -f1)

            # Extract imports
            grep -E "^import |^from .* import" "$file" 2>/dev/null | while read -r line; do
                local imported=$(echo "$line" | sed -E 's/^import //;s/^from ([^ ]+).*/\1/' | cut -d. -f1)

                if [ -n "$imported" ] && [ "$imported" != "import" ]; then
                    # Add nodes
                    add_node "repo-${repo_name}" "repository" "$repo_name" "{}" 2>/dev/null || true
                    add_node "package-${imported}" "package" "$imported" "{}" 2>/dev/null || true

                    # Add edge
                    add_edge "repo-${repo_name}" "package-${imported}" "imports" 0.8 2>/dev/null || true
                fi
            done
        done
    fi

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "knowledge-graph" "Built knowledge graph from codebase dependencies" "coordination,graph,build" 2>/dev/null || true
    fi

    echo -e "${GREEN}[GRAPH]${NC} Graph build complete!"
}

# Visualize subgraph
visualize() {
    local component="$1"

    echo -e "${BLUE}[GRAPH]${NC} Generating DOT graph for: ${component}"
    echo ""

    cat <<EOF
digraph KnowledgeGraph {
    rankdir=LR;
    node [shape=box, style=filled, fillcolor=lightblue];

EOF

    # Get all connected nodes
    sqlite3 "$GRAPH_DB" <<SQL
SELECT DISTINCT
    printf('    "%s" [label="%s\\n(%s)", fillcolor="%s"];',
        from_node,
        (SELECT name FROM nodes WHERE id = e.from_node),
        (SELECT type FROM nodes WHERE id = e.from_node),
        CASE (SELECT type FROM nodes WHERE id = e.from_node)
            WHEN 'repository' THEN 'lightgreen'
            WHEN 'package' THEN 'lightblue'
            WHEN 'service' THEN 'lightyellow'
            WHEN 'database' THEN 'lightcoral'
            ELSE 'lightgray'
        END
    )
FROM edges e
WHERE from_node IN (
    SELECT id FROM nodes WHERE name LIKE '%${component}%'
    UNION
    SELECT from_node FROM edges WHERE to_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
    UNION
    SELECT to_node FROM edges WHERE from_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
);

SELECT DISTINCT
    printf('    "%s" -> "%s" [label="%s"];',
        from_node,
        to_node,
        relationship
    )
FROM edges
WHERE from_node IN (
    SELECT id FROM nodes WHERE name LIKE '%${component}%'
    UNION
    SELECT from_node FROM edges WHERE to_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
)
   OR to_node IN (
    SELECT id FROM nodes WHERE name LIKE '%${component}%'
    UNION
    SELECT to_node FROM edges WHERE from_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
);
SQL

    echo "}"
    echo ""
    echo -e "${GREEN}[GRAPH]${NC} Save output to .dot file and render with: dot -Tpng graph.dot -o graph.png"
}

# Statistics
show_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         🕸️  KNOWLEDGE GRAPH STATISTICS 🕸️            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_nodes=$(sqlite3 "$GRAPH_DB" "SELECT COUNT(*) FROM nodes;")
    local total_edges=$(sqlite3 "$GRAPH_DB" "SELECT COUNT(*) FROM edges;")

    echo -e "${GREEN}Total Nodes:${NC}     $total_nodes"
    echo -e "${GREEN}Total Edges:${NC}     $total_edges"
    echo ""

    echo -e "${BLUE}Nodes by Type:${NC}"
    sqlite3 -column -header "$GRAPH_DB" <<EOF
SELECT type, COUNT(*) as count
FROM nodes
GROUP BY type
ORDER BY count DESC;
EOF

    echo ""
    echo -e "${BLUE}Relationships:${NC}"
    sqlite3 -column -header "$GRAPH_DB" <<EOF
SELECT relationship, COUNT(*) as count
FROM edges
GROUP BY relationship
ORDER BY count DESC;
EOF

    echo ""
    echo -e "${BLUE}Most Connected Nodes:${NC}"
    sqlite3 -column -header "$GRAPH_DB" <<EOF
SELECT
    n.name,
    n.type,
    (SELECT COUNT(*) FROM edges WHERE from_node = n.id OR to_node = n.id) as connections
FROM nodes n
ORDER BY connections DESC
LIMIT 10;
EOF
}

# Help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Knowledge Graph System [GRAPH]${NC}

USAGE:
    blackroad-knowledge-graph.sh <command> [options]

COMMANDS:
    init                        Initialize knowledge graph
    build                       Build graph from codebase
    depends-on <component>      What depends on this component?
    required-by <component>     What does this component require?
    impacts <component>         Impact analysis (what breaks?)
    connected-to <component>    All connected components
    visualize <component>       Generate DOT graph visualization
    stats                       Show graph statistics
    add-node <id> <type> <name> Add a node
    add-edge <from> <to> <rel>  Add an edge
    help                        Show this help

EXAMPLES:
    # Initialize
    blackroad-knowledge-graph.sh init

    # Build from code
    blackroad-knowledge-graph.sh build

    # Query dependencies
    blackroad-knowledge-graph.sh depends-on "user-auth"
    blackroad-knowledge-graph.sh required-by "database"
    blackroad-knowledge-graph.sh impacts "api-gateway"
    blackroad-knowledge-graph.sh connected-to "cloudflare-kv"

    # Visualize
    blackroad-knowledge-graph.sh visualize "authentication" > auth.dot
    dot -Tpng auth.dot -o auth.png

    # Manual graph building
    blackroad-knowledge-graph.sh add-node "api-auth" "service" "Authentication API"
    blackroad-knowledge-graph.sh add-edge "api-auth" "db-users" "queries"

DATABASE: $GRAPH_DB
EOF
}

# Main command handler
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_graph
            ;;
        build)
            build_from_code
            ;;
        depends-on)
            depends_on "$2"
            ;;
        required-by)
            required_by "$2"
            ;;
        impacts)
            impacts "$2"
            ;;
        connected-to)
            connected_to "$2"
            ;;
        visualize)
            visualize "$2"
            ;;
        stats)
            show_stats
            ;;
        add-node)
            add_node "$2" "$3" "$4" "${5:-{}}"
            ;;
        add-edge)
            add_edge "$2" "$3" "$4" "${5:-1.0}"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[GRAPH]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
