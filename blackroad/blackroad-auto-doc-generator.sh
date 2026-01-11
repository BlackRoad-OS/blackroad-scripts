#!/bin/bash
# BlackRoad Automated Documentation Generator
# Automatically generates comprehensive documentation for all repos
# Version: 1.0.0

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"
DOCS_DB="$HOME/.blackroad/auto-docs/docs.db"

# Initialize database
init_db() {
    mkdir -p "$(dirname "$DOCS_DB")"

    sqlite3 "$DOCS_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS documentation_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT NOT NULL,
    generated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    files_documented INTEGER DEFAULT 0,
    functions_documented INTEGER DEFAULT 0,
    classes_documented INTEGER DEFAULT 0,
    doc_coverage REAL DEFAULT 0,
    output_format TEXT,
    status TEXT DEFAULT 'completed'
);

CREATE INDEX IF NOT EXISTS idx_docs_repo ON documentation_runs(repo);
SQL

    echo -e "${GREEN}[AUTO-DOCS]${NC} Database initialized!"
}

# Extract functions from JavaScript/TypeScript
extract_js_functions() {
    local file="$1"

    grep -E 'function [a-zA-Z_][a-zA-Z0-9_]*|const [a-zA-Z_][a-zA-Z0-9_]*\s*=\s*\(|export (async )?function' "$file" 2>/dev/null | \
    sed 's/^[[:space:]]*//' | \
    sed 's/{.*//' | \
    head -20
}

# Extract functions from Python
extract_py_functions() {
    local file="$1"

    grep -E '^def [a-zA-Z_][a-zA-Z0-9_]*|^class [a-zA-Z_][a-zA-Z0-9_]*' "$file" 2>/dev/null | \
    sed 's/^[[:space:]]*//' | \
    sed 's/:.*//' | \
    head -20
}

# Generate README for a repository
generate_readme() {
    local repo_path="$1"
    local repo_name="$(basename "$repo_path")"

    echo -e "${PURPLE}━━━ Generating docs for $repo_name ━━━${NC}"

    cd "$repo_path"

    # Detect language
    local primary_lang="Unknown"
    if [ -f "package.json" ]; then
        primary_lang="JavaScript/TypeScript"
    elif [ -f "requirements.txt" ] || [ -f "setup.py" ]; then
        primary_lang="Python"
    elif [ -f "go.mod" ]; then
        primary_lang="Go"
    fi

    # Count files
    local total_files=$(find . -type f \( -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" \) 2>/dev/null | wc -l | tr -d ' ')

    # Extract functions and classes
    local functions=""
    if [ "$primary_lang" = "JavaScript/TypeScript" ]; then
        functions=$(find . -name "*.js" -o -name "*.ts" 2>/dev/null | head -5 | xargs -I {} bash -c 'extract_js_functions "{}"' 2>/dev/null || echo "")
    elif [ "$primary_lang" = "Python" ]; then
        functions=$(find . -name "*.py" 2>/dev/null | head -5 | xargs -I {} bash -c 'extract_py_functions "{}"' 2>/dev/null || echo "")
    fi

    # Generate README
    local readme_file="$repo_path/AUTO_GENERATED_DOCS.md"

    cat > "$readme_file" <<EOF
# $repo_name

> Auto-generated documentation by BlackRoad Auto-Docs

## 📋 Overview

**Language:** $primary_lang
**Total Code Files:** $total_files
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')

## 📂 Project Structure

\`\`\`
$(tree -L 2 -I 'node_modules|.git|dist|build' . 2>/dev/null || find . -maxdepth 2 -type d -not -path '*/\.*' -not -path '*/node_modules*' 2>/dev/null | head -20)
\`\`\`

## 🚀 Quick Start

### Installation

\`\`\`bash
# Clone the repository
git clone <repository-url>
cd $repo_name

# Install dependencies
$(if [ -f "package.json" ]; then echo "npm install"; elif [ -f "requirements.txt" ]; then echo "pip install -r requirements.txt"; elif [ -f "go.mod" ]; then echo "go mod download"; else echo "# Add installation commands"; fi)
\`\`\`

### Usage

\`\`\`bash
# Run the application
$(if [ -f "package.json" ]; then echo "npm start"; elif [ -f "setup.py" ]; then echo "python main.py"; elif [ -f "go.mod" ]; then echo "go run ."; else echo "# Add usage commands"; fi)
\`\`\`

## 📚 API Documentation

$(if [ -n "$functions" ]; then echo "### Functions

\`\`\`
$functions
\`\`\`

> Note: This is a partial list. See source files for complete documentation."; else echo "> API documentation to be added."; fi)

## 🧪 Testing

\`\`\`bash
# Run tests
$(if [ -f "package.json" ]; then echo "npm test"; elif [ -f "pytest.ini" ]; then echo "pytest"; elif [ -f "go.mod" ]; then echo "go test ./..."; else echo "# Add test commands"; fi)
\`\`\`

## 🔧 Configuration

$(if [ -f ".env.example" ]; then echo "Environment variables:

\`\`\`bash
$(cat .env.example 2>/dev/null | head -10)
\`\`\`"; else echo "> Configuration documentation to be added."; fi)

## 🌌 BlackRoad Coordination

This repository is integrated with **BlackRoad Coordination v2.0**!

### For Claude Instances

Before working on this repo:
\`\`\`bash
# Check for conflicts
~/blackroad-conflict-detector.sh check $repo_name

# Claim work
~/blackroad-conflict-detector.sh claim $repo_name "Your task"

# When done
~/blackroad-conflict-detector.sh release $repo_name
\`\`\`

### Automation Tools Available
- 🔄 Dependency updates: \`~/blackroad-dependency-updater.sh\`
- 📊 Code quality analysis: \`~/blackroad-code-quality-analyzer.sh\`
- 🧪 Automated testing: \`~/blackroad-auto-test-runner.sh\`
- 🤖 Auto-PR generation: \`~/blackroad-auto-pr-generator.sh\`

## 📈 Project Stats

- **Files:** $total_files code files
- **Language:** $primary_lang
- **Coordination:** $(if [ -f ".blackroad-config.json" ]; then echo "✅ Enabled"; else echo "⚠️ Not configured"; fi)

## 🤝 Contributing

This project uses BlackRoad coordination hooks:
1. Pre-commit: Checks for conflicts with other Claude instances
2. Post-commit: Logs commits to coordination systems
3. Post-checkout: Updates local coordination data

## 📄 License

> License information to be added.

---

**Auto-generated by BlackRoad Auto-Docs**
**Last Updated:** $(date '+%Y-%m-%d %H:%M:%S')

🌌 Part of BlackRoad Coordination v2.0
EOF

    echo -e "${GREEN}  ✓ Documentation generated: AUTO_GENERATED_DOCS.md${NC}"

    # Log to database
    sqlite3 "$DOCS_DB" <<SQL
INSERT INTO documentation_runs (repo, files_documented, output_format)
VALUES ('$repo_name', $total_files, 'markdown');
SQL

    echo ""
}

# Generate docs for all repositories
generate_all_docs() {
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}║   📚 AUTOMATED DOCUMENTATION GENERATOR 📚              ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_repos=0

    if [ -d "$PROJECTS_DIR" ]; then
        find "$PROJECTS_DIR" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            ((total_repos++))
            generate_readme "$repo_path"
        done
    fi

    echo -e "${GREEN}━━━ Documentation Generation Complete ━━━${NC}"
    echo ""

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log completed "auto-docs-generation" "Generated automated documentation for all repositories. Each repo now has AUTO_GENERATED_DOCS.md with structure, API docs, and coordination instructions." "documentation,automation" 2>/dev/null || true
    fi
}

# Generate API documentation
generate_api_docs() {
    local repo_path="$1"
    local output_file="${2:-API_DOCS.md}"

    if [ -z "$repo_path" ]; then
        echo -e "${RED}[AUTO-DOCS]${NC} Repository path required"
        return 1
    fi

    local repo_name="$(basename "$repo_path")"
    echo -e "${CYAN}Generating API docs for $repo_name...${NC}"

    cd "$repo_path"

    cat > "$output_file" <<EOF
# API Documentation: $repo_name

> Auto-generated by BlackRoad Auto-Docs

## Endpoints

$(find . -name "*.js" -o -name "*.ts" 2>/dev/null | xargs grep -h "app\.\(get\|post\|put\|delete\|patch\)" 2>/dev/null | head -20 || echo "> No API endpoints detected.")

## Functions

$(find . -name "*.js" -o -name "*.ts" 2>/dev/null | head -10 | while read -r file; do
    echo "### $(basename "$file")"
    echo ""
    echo "\`\`\`javascript"
    extract_js_functions "$file" 2>/dev/null || echo "// No functions found"
    echo "\`\`\`"
    echo ""
done)

---

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
EOF

    echo -e "${GREEN}✓ API docs generated: $output_file${NC}"
}

# Show documentation statistics
show_stats() {
    echo -e "${CYAN}━━━ Documentation Statistics ━━━${NC}"
    echo ""

    if [ -f "$DOCS_DB" ]; then
        echo -e "${PURPLE}Overall Summary:${NC}"
        sqlite3 -column "$DOCS_DB" "
            SELECT
                COUNT(DISTINCT repo) as repos_documented,
                SUM(files_documented) as total_files,
                ROUND(AVG(files_documented), 1) as avg_files_per_repo
            FROM documentation_runs;
        " 2>/dev/null || echo "No data"

        echo ""
        echo -e "${PURPLE}Recent Documentation Runs:${NC}"
        sqlite3 -column "$DOCS_DB" "
            SELECT
                substr(repo, 1, 35) as repository,
                files_documented as files,
                output_format as format,
                substr(generated_at, 1, 19) as generated
            FROM documentation_runs
            ORDER BY generated_at DESC
            LIMIT 15;
        " 2>/dev/null || echo "No recent runs"
    else
        echo "No documentation data found. Run 'generate-all' first."
    fi

    echo ""
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Automated Documentation Generator${NC}

Automatically generates comprehensive documentation for all repositories.

USAGE:
    blackroad-auto-doc-generator.sh <command> [args]

COMMANDS:
    init                        Initialize documentation database
    generate-all                Generate docs for all repositories
    generate-readme <repo>      Generate README for specific repo
    generate-api <repo> [file]  Generate API documentation
    stats                       Show documentation statistics
    help                        Show this help

EXAMPLES:
    # Generate docs for all repos
    blackroad-auto-doc-generator.sh generate-all

    # Generate for one repo
    blackroad-auto-doc-generator.sh generate-readme ~/projects/blackroad-api

    # Generate API docs
    blackroad-auto-doc-generator.sh generate-api ~/projects/blackroad-api

    # View stats
    blackroad-auto-doc-generator.sh stats

FEATURES:
    ✓ Automatic README generation
    ✓ API documentation extraction
    ✓ Project structure visualization
    ✓ Function/class listing
    ✓ Quick start guides
    ✓ Coordination instructions
    ✓ Multi-language support
    ✓ Automatic updates

GENERATED DOCUMENTATION INCLUDES:
    ✓ Project overview
    ✓ Installation instructions
    ✓ Usage examples
    ✓ API documentation
    ✓ Testing instructions
    ✓ Configuration guide
    ✓ BlackRoad coordination info
    ✓ Contributing guidelines

DATABASE: $DOCS_DB
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        generate-all)
            init_db
            generate_all_docs
            ;;
        generate-readme)
            if [ -z "$2" ]; then
                echo -e "${RED}[AUTO-DOCS]${NC} Repository path required"
                exit 1
            fi
            init_db
            generate_readme "$2"
            ;;
        generate-api)
            init_db
            generate_api_docs "$2" "$3"
            ;;
        stats)
            show_stats
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[AUTO-DOCS]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# Export functions for subshells
export -f extract_js_functions
export -f extract_py_functions

main "$@"
