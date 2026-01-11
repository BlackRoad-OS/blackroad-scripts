#!/bin/bash
# BlackRoad Visual Dependency Graph Generator
# Creates beautiful visual graphs of component dependencies
# Version: 1.0.0

set -e

GRAPH_DB="$HOME/.blackroad/graph/knowledge.db"
OUTPUT_DIR="$HOME/.blackroad/visualizations"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Initialize
init_viz() {
    mkdir -p "$OUTPUT_DIR"
    echo -e "${GREEN}[VIZ]${NC} Visualization directory: $OUTPUT_DIR"
}

# Generate full system graph
generate_full_graph() {
    local output="${1:-full-system.dot}"

    echo -e "${BLUE}[VIZ]${NC} Generating full system dependency graph..."

    cat > "$OUTPUT_DIR/$output" <<'EOF'
digraph BlackRoadSystem {
    // Graph settings
    rankdir=LR;
    bgcolor="#0a0a0a";
    node [fontname="SF Pro Display", fontsize=12];
    edge [fontname="SF Pro Display", fontsize=10];

    // Style definitions
    node [shape=box, style="filled,rounded", fillcolor="#1a1a1a", fontcolor="#ffffff", color="#FF1D6C", penwidth=2];
    edge [color="#F5A623", penwidth=1.5];

EOF

    # Add nodes from graph database
    if [ -f "$GRAPH_DB" ]; then
        sqlite3 "$GRAPH_DB" "SELECT DISTINCT id, type, name FROM nodes;" | while IFS='|' read -r id type name; do
            local color="#FF1D6C"
            local shape="box"

            case "$type" in
                repository) color="#2979FF"; shape="box" ;;
                service) color="#9C27B0"; shape="ellipse" ;;
                database) color="#F5A623"; shape="cylinder" ;;
                api) color="#FF1D6C"; shape="component" ;;
                *) color="#666666" ;;
            esac

            echo "    \"$id\" [label=\"$name\\n($type)\", fillcolor=\"$color\", shape=$shape];" >> "$OUTPUT_DIR/$output"
        done

        # Add edges
        sqlite3 "$GRAPH_DB" "SELECT from_node, to_node, relationship, strength FROM edges;" | while IFS='|' read -r from to rel strength; do
            local penwidth=$(echo "1 + ($strength * 2)" | bc)
            echo "    \"$from\" -> \"$to\" [label=\"$rel\", penwidth=$penwidth];" >> "$OUTPUT_DIR/$output"
        done
    fi

    echo "}" >> "$OUTPUT_DIR/$output"

    echo -e "${GREEN}[VIZ]${NC} Generated: $OUTPUT_DIR/$output"

    # Try to render if graphviz available
    if command -v dot &> /dev/null; then
        echo -e "${BLUE}[VIZ]${NC} Rendering to PNG..."
        dot -Tpng "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.png" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} PNG created: $OUTPUT_DIR/${output%.dot}.png" || \
            echo -e "${YELLOW}[VIZ]${NC} PNG rendering failed"

        # Also create SVG
        dot -Tsvg "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.svg" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} SVG created: $OUTPUT_DIR/${output%.dot}.svg"
    else
        echo -e "${YELLOW}[VIZ]${NC} Install graphviz to render: brew install graphviz"
    fi
}

# Generate component-specific graph
generate_component_graph() {
    local component="$1"
    local output="${2:-${component}-deps.dot}"

    echo -e "${BLUE}[VIZ]${NC} Generating dependency graph for: $component"

    cat > "$OUTPUT_DIR/$output" <<EOF
digraph ${component//-/_}Dependencies {
    // BlackRoad Brand Colors
    rankdir=TB;
    bgcolor="#000000";
    node [fontname="SF Pro Display", fontsize=14, fontcolor="#ffffff"];
    edge [fontname="SF Pro Display", fontsize=11];

    // Center node (the component itself)
    "$component" [
        shape=box,
        style="filled,rounded",
        fillcolor="#FF1D6C",
        color="#F5A623",
        penwidth=3,
        fontsize=16
    ];

EOF

    # Find dependencies
    if [ -f "$GRAPH_DB" ]; then
        # Things that depend on this component
        echo "    // Dependencies (things that use $component)" >> "$OUTPUT_DIR/$output"
        sqlite3 "$GRAPH_DB" "
            SELECT DISTINCT n.name, e.relationship
            FROM edges e
            JOIN nodes n ON e.from_node = n.id
            WHERE e.to_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
            LIMIT 10;
        " | while IFS='|' read -r dep_name relationship; do
            echo "    \"$dep_name\" [fillcolor=\"#2979FF\", style=\"filled,rounded\", color=\"#F5A623\"];" >> "$OUTPUT_DIR/$output"
            echo "    \"$dep_name\" -> \"$component\" [label=\"$relationship\", color=\"#F5A623\"];" >> "$OUTPUT_DIR/$output"
        done

        # Things this component depends on
        echo "    // Requirements (things $component uses)" >> "$OUTPUT_DIR/$output"
        sqlite3 "$GRAPH_DB" "
            SELECT DISTINCT n.name, e.relationship
            FROM edges e
            JOIN nodes n ON e.to_node = n.id
            WHERE e.from_node IN (SELECT id FROM nodes WHERE name LIKE '%${component}%')
            LIMIT 10;
        " | while IFS='|' read -r req_name relationship; do
            echo "    \"$req_name\" [fillcolor=\"#9C27B0\", style=\"filled,rounded\", color=\"#F5A623\"];" >> "$OUTPUT_DIR/$output"
            echo "    \"$component\" -> \"$req_name\" [label=\"$relationship\", color=\"#2979FF\"];" >> "$OUTPUT_DIR/$output"
        done
    fi

    echo "}" >> "$OUTPUT_DIR/$output"

    echo -e "${GREEN}[VIZ]${NC} Generated: $OUTPUT_DIR/$output"

    # Render
    if command -v dot &> /dev/null; then
        dot -Tpng "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.png" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} PNG: $OUTPUT_DIR/${output%.dot}.png"
        dot -Tsvg "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.svg" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} SVG: $OUTPUT_DIR/${output%.dot}.svg"
    fi
}

# Generate active work visualization
generate_active_work_viz() {
    local output="${1:-active-work.dot}"

    echo -e "${BLUE}[VIZ]${NC} Generating active work visualization..."

    cat > "$OUTPUT_DIR/$output" <<'EOF'
digraph ActiveWork {
    rankdir=TB;
    bgcolor="#0a0a0a";
    node [fontname="SF Pro Display", fontsize=12];
    edge [fontname="SF Pro Display"];

    // Legend
    subgraph cluster_legend {
        label="Legend";
        fontcolor="#ffffff";
        style=filled;
        fillcolor="#1a1a1a";
        color="#F5A623";

        agent [label="Claude Agent", shape=octagon, fillcolor="#2979FF", style="filled"];
        repo [label="Repository", shape=box, fillcolor="#FF1D6C", style="filled,rounded"];
    }

EOF

    # Add active agents and their work
    if [ -f ~/.blackroad/conflict/locks.db ]; then
        sqlite3 ~/.blackroad/conflict/locks.db "
            SELECT DISTINCT agent_id, resource, description
            FROM work_claims
            WHERE status='active';
        " | while IFS='|' read -r agent resource desc; do
            local agent_short=$(echo "$agent" | cut -c1-30)
            echo "    \"$agent_short\" [shape=octagon, fillcolor=\"#2979FF\", style=\"filled\", fontcolor=\"#ffffff\"];" >> "$OUTPUT_DIR/$output"
            echo "    \"$resource\" [shape=box, fillcolor=\"#FF1D6C\", style=\"filled,rounded\", fontcolor=\"#ffffff\"];" >> "$OUTPUT_DIR/$output"
            echo "    \"$agent_short\" -> \"$resource\" [label=\"$desc\", color=\"#F5A623\"];" >> "$OUTPUT_DIR/$output"
        done
    fi

    echo "}" >> "$OUTPUT_DIR/$output"

    echo -e "${GREEN}[VIZ]${NC} Generated: $OUTPUT_DIR/$output"

    if command -v dot &> /dev/null; then
        dot -Tpng "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.png" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} PNG: $OUTPUT_DIR/${output%.dot}.png"
    fi
}

# Generate infrastructure map
generate_infra_map() {
    local output="${1:-infrastructure-map.dot}"

    echo -e "${BLUE}[VIZ]${NC} Generating infrastructure map..."

    cat > "$OUTPUT_DIR/$output" <<'EOF'
digraph InfrastructureMap {
    rankdir=TB;
    bgcolor="#000000";
    node [fontname="SF Pro Display", fontsize=13, fontcolor="#ffffff"];
    edge [fontname="SF Pro Display", fontcolor="#F5A623"];

    // GitHub layer
    subgraph cluster_github {
        label="GitHub (66 repos)";
        style=filled;
        fillcolor="#1a1a1a";
        color="#2979FF";
        fontcolor="#ffffff";
        fontsize=16;

EOF

    # Add GitHub repos from index
    if [ -f ~/.blackroad/index/assets.db ]; then
        sqlite3 ~/.blackroad/index/assets.db "
            SELECT DISTINCT org, COUNT(*) as count
            FROM github_repos
            GROUP BY org
            LIMIT 15;
        " | while IFS='|' read -r org count; do
            echo "        \"gh_$org\" [label=\"$org\\n($count repos)\", shape=folder, fillcolor=\"#2979FF\", style=\"filled\"];" >> "$OUTPUT_DIR/$output"
        done
    fi

    cat >> "$OUTPUT_DIR/$output" <<'EOF'
    }

    // Cloudflare layer
    subgraph cluster_cloudflare {
        label="Cloudflare (16 zones)";
        style=filled;
        fillcolor="#1a1a1a";
        color="#F5A623";
        fontcolor="#ffffff";
        fontsize=16;

EOF

    if [ -f ~/.blackroad/index/assets.db ]; then
        sqlite3 ~/.blackroad/index/assets.db "
            SELECT name, resource_type
            FROM cloudflare_resources
            LIMIT 10;
        " | while IFS='|' read -r name type; do
            echo "        \"cf_$name\" [label=\"$name\\n($type)\", shape=component, fillcolor=\"#F5A623\", style=\"filled\"];" >> "$OUTPUT_DIR/$output"
        done
    fi

    cat >> "$OUTPUT_DIR/$output" <<'EOF'
    }

    // Pi cluster
    subgraph cluster_pi {
        label="Pi Cluster (3 systems)";
        style=filled;
        fillcolor="#1a1a1a";
        color="#9C27B0";
        fontcolor="#ffffff";
        fontsize=16;

        pi_lucidia [label="lucidia\\n192.168.4.38", shape=box3d, fillcolor="#9C27B0", style="filled"];
        pi_blackroad [label="blackroad-pi\\n192.168.4.64", shape=box3d, fillcolor="#9C27B0", style="filled"];
        pi_alt [label="lucidia-alt\\n192.168.4.99", shape=box3d, fillcolor="#9C27B0", style="filled"];
    }
}
EOF

    echo -e "${GREEN}[VIZ]${NC} Generated: $OUTPUT_DIR/$output"

    if command -v dot &> /dev/null; then
        dot -Tpng "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.png" -Gdpi=150 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} PNG: $OUTPUT_DIR/${output%.dot}.png"
        dot -Tsvg "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.svg" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} SVG: $OUTPUT_DIR/${output%.dot}.svg"
    fi
}

# Generate coordination systems map
generate_coordination_map() {
    local output="${1:-coordination-systems.dot}"

    echo -e "${BLUE}[VIZ]${NC} Generating coordination systems map..."

    cat > "$OUTPUT_DIR/$output" <<'EOF'
digraph CoordinationSystems {
    rankdir=TB;
    bgcolor="#000000";
    node [fontname="SF Pro Display", fontsize=14, fontcolor="#ffffff"];
    edge [fontname="SF Pro Display", fontcolor="#F5A623"];

    // Core
    core [label="Claude Agent", shape=octagon, fillcolor="#FF1D6C", style="filled,bold", penwidth=3, fontsize=16];

    // Systems
    index [label="[INDEX]\nAsset Search", shape=cylinder, fillcolor="#2979FF", style="filled"];
    graph [label="[GRAPH]\nDependencies", shape=component, fillcolor="#9C27B0", style="filled"];
    semantic [label="[SEMANTIC]\nNL Search", shape=box, fillcolor="#F5A623", style="filled,rounded"];
    health [label="[HEALTH]\nMonitoring", shape=box, fillcolor="#00BCD4", style="filled,rounded"];
    conflict [label="[CONFLICT]\nDetection", shape=diamond, fillcolor="#FF5722", style="filled"];
    router [label="[ROUTER]\nTask Routing", shape=parallelogram, fillcolor="#4CAF50", style="filled"];
    timeline [label="[TIMELINE]\nActivity", shape=box, fillcolor="#FFC107", style="filled,rounded"];
    intelligence [label="[INTELLIGENCE]\nLearning", shape=hexagon, fillcolor="#E91E63", style="filled"];

    // Connections
    core -> index [label="searches", color="#2979FF"];
    core -> graph [label="queries", color="#9C27B0"];
    core -> semantic [label="asks", color="#F5A623"];
    core -> health [label="checks", color="#00BCD4"];
    core -> conflict [label="claims", color="#FF5722"];
    core -> router [label="registers", color="#4CAF50"];
    core -> timeline [label="logs", color="#FFC107"];
    core -> intelligence [label="learns", color="#E91E63"];

    // Inter-system connections
    index -> graph [style=dashed, color="#666666"];
    semantic -> timeline [style=dashed, color="#666666"];
    conflict -> router [style=dashed, color="#666666"];
    intelligence -> router [style=dashed, color="#666666"];
}
EOF

    echo -e "${GREEN}[VIZ]${NC} Generated: $OUTPUT_DIR/$output"

    if command -v dot &> /dev/null; then
        dot -Tpng "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.png" -Gdpi=150 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} PNG: $OUTPUT_DIR/${output%.dot}.png"
        dot -Tsvg "$OUTPUT_DIR/$output" -o "$OUTPUT_DIR/${output%.dot}.svg" 2>/dev/null && \
            echo -e "${GREEN}[VIZ]${NC} SVG: $OUTPUT_DIR/${output%.dot}.svg"
    fi
}

# List visualizations
list_viz() {
    echo -e "${BLUE}[VIZ]${NC} Available visualizations:"
    echo ""

    if [ -d "$OUTPUT_DIR" ]; then
        ls -lh "$OUTPUT_DIR"/*.{dot,png,svg} 2>/dev/null | awk '{print "  " $9}' || echo "  No visualizations yet"
    else
        echo "  No visualizations yet"
    fi
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Visual Dependency Graph Generator${NC}

USAGE:
    blackroad-visualize-dependencies.sh <command> [options]

COMMANDS:
    init                        Initialize visualization directory
    full [output.dot]           Generate full system graph
    component <name> [out.dot]  Generate component dependency graph
    active [output.dot]         Generate active work visualization
    infra [output.dot]          Generate infrastructure map
    systems [output.dot]        Generate coordination systems map
    list                        List generated visualizations
    help                        Show this help

EXAMPLES:
    # Generate full system graph
    blackroad-visualize-dependencies.sh full

    # Component dependencies
    blackroad-visualize-dependencies.sh component "user-auth"

    # Active work
    blackroad-visualize-dependencies.sh active

    # Infrastructure map
    blackroad-visualize-dependencies.sh infra

    # Coordination systems
    blackroad-visualize-dependencies.sh systems

    # List all
    blackroad-visualize-dependencies.sh list

OUTPUT:
    Directory: $OUTPUT_DIR
    Formats: .dot (source), .png (image), .svg (vector)

REQUIRES:
    graphviz (for rendering): brew install graphviz

BRAND COLORS:
    Hot Pink    #FF1D6C  (primary)
    Amber       #F5A623  (secondary)
    Violet      #9C27B0  (accent)
    Electric    #2979FF  (info)
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_viz
            ;;
        full)
            init_viz
            generate_full_graph "$2"
            ;;
        component)
            if [ -z "$2" ]; then
                echo -e "${RED}[VIZ]${NC} Component name required"
                exit 1
            fi
            init_viz
            generate_component_graph "$2" "$3"
            ;;
        active)
            init_viz
            generate_active_work_viz "$2"
            ;;
        infra)
            init_viz
            generate_infra_map "$2"
            ;;
        systems)
            init_viz
            generate_coordination_map "$2"
            ;;
        list)
            list_viz
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[VIZ]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
