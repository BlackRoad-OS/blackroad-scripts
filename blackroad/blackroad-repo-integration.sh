#!/bin/bash
# BlackRoad Repository Integration Framework
# Makes EVERY repo coordination-aware!
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
INTEGRATION_DIR="$HOME/.blackroad/repo-integration"
HOOKS_TEMPLATE_DIR="$INTEGRATION_DIR/hooks"
GITHUB_ORGS="BlackRoad-OS BlackRoad-AI BlackRoad-Cloud BlackRoad-Security BlackRoad-Labs"

# Initialize
init_integration() {
    echo -e "${BLUE}[REPO-INTEGRATION]${NC} Initializing repository integration framework..."

    mkdir -p "$INTEGRATION_DIR" "$HOOKS_TEMPLATE_DIR"

    echo -e "${GREEN}[REPO-INTEGRATION]${NC} Framework initialized!"
}

# Create git hooks template
create_hooks_template() {
    echo -e "${BLUE}[REPO-INTEGRATION]${NC} Creating git hooks templates..."

    # Pre-commit hook
    cat > "$HOOKS_TEMPLATE_DIR/pre-commit" <<'HOOK_SCRIPT'
#!/bin/bash
# BlackRoad Coordination Pre-Commit Hook
# Auto-checks for conflicts before committing

REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
AGENT_ID="${MY_CLAUDE:-unknown-agent}"

# Check for conflicts with other Claude instances
if [ -f ~/blackroad-conflict-detector.sh ]; then
    echo "🔍 Checking for conflicts..."

    if ! ~/blackroad-conflict-detector.sh check "$REPO_NAME" 2>/dev/null; then
        echo ""
        echo "⚠️  WARNING: Another Claude instance may be working on this repo!"
        echo "Do you want to continue? (y/n)"
        read -r response

        if [ "$response" != "y" ]; then
            echo "❌ Commit cancelled. Coordinate with other agents first."
            exit 1
        fi
    fi
fi

# Log to timeline
if [ -f ~/blackroad-timeline.sh ]; then
    ~/blackroad-timeline.sh add-event "git-commit" "$REPO_NAME" "$AGENT_ID" "$REPO_NAME" "preparing commit" "Staged changes for commit" "git,commit" 2>/dev/null || true
fi

echo "✅ Pre-commit checks passed!"
HOOK_SCRIPT

    # Post-commit hook
    cat > "$HOOKS_TEMPLATE_DIR/post-commit" <<'HOOK_SCRIPT'
#!/bin/bash
# BlackRoad Coordination Post-Commit Hook
# Auto-logs commits to coordination systems

REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
AGENT_ID="${MY_CLAUDE:-unknown-agent}"
COMMIT_MSG=$(git log -1 --pretty=%B)
COMMIT_HASH=$(git rev-parse --short HEAD)

# Log to memory
if [ -f ~/memory-system.sh ]; then
    ~/memory-system.sh log updated "$REPO_NAME" "Commit $COMMIT_HASH: $COMMIT_MSG" "git,commit,$AGENT_ID" 2>/dev/null || true
fi

# Update timeline
if [ -f ~/blackroad-timeline.sh ]; then
    ~/blackroad-timeline.sh import-git 2>/dev/null || true
fi

# Award points if leaderboard exists
if [ -f ~/blackroad-performance-leaderboard.sh ]; then
    ~/blackroad-performance-leaderboard.sh award "commit" 10 "$REPO_NAME: $COMMIT_MSG" 2>/dev/null || true
fi

echo "📝 Logged to coordination systems!"
HOOK_SCRIPT

    # Post-checkout hook
    cat > "$HOOKS_TEMPLATE_DIR/post-checkout" <<'HOOK_SCRIPT'
#!/bin/bash
# BlackRoad Coordination Post-Checkout Hook
# Updates local coordination data

REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")

# Refresh index for this repo
if [ -f ~/blackroad-universal-index.sh ]; then
    echo "🔄 Refreshing coordination index..."
    ~/blackroad-universal-index.sh refresh 2>/dev/null &
fi
HOOK_SCRIPT

    chmod +x "$HOOKS_TEMPLATE_DIR"/*

    echo -e "${GREEN}[REPO-INTEGRATION]${NC} Git hooks templates created!"
}

# Install hooks in a repository
install_hooks() {
    local repo_path="$1"

    if [ ! -d "$repo_path/.git" ]; then
        echo -e "${RED}[REPO-INTEGRATION]${NC} Not a git repository: $repo_path"
        return 1
    fi

    local repo_name=$(basename "$repo_path")
    echo -e "${CYAN}  Installing hooks in: $repo_name${NC}"

    # Copy hooks
    for hook in pre-commit post-commit post-checkout; do
        cp "$HOOKS_TEMPLATE_DIR/$hook" "$repo_path/.git/hooks/"
        chmod +x "$repo_path/.git/hooks/$hook"
    done

    # Create coordination config
    cat > "$repo_path/.blackroad-config.json" <<EOF
{
  "repo_name": "$repo_name",
  "coordination_enabled": true,
  "auto_conflict_check": true,
  "auto_index_refresh": true,
  "auto_timeline_update": true,
  "integration_version": "1.0.0",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    echo -e "${GREEN}    ✓${NC} Hooks installed!"
}

# Install in all repos
install_in_all_repos() {
    echo -e "${BLUE}[REPO-INTEGRATION]${NC} Installing coordination hooks in ALL repositories..."
    echo ""

    local total=0
    local success=0

    # Find all git repos
    if [ -d ~/projects ]; then
        find ~/projects -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            ((total++))

            if install_hooks "$repo_path"; then
                ((success++))
            fi
        done
    fi

    echo ""
    echo -e "${GREEN}[REPO-INTEGRATION]${NC} Installation complete!"
    echo -e "${CYAN}Repositories processed:${NC} $total"
    echo -e "${CYAN}Successfully installed:${NC} $success"

    # Log to memory
    if [ -f ~/memory-system.sh ]; then
        ~/memory-system.sh log updated "repo-integration" "Installed coordination hooks in $success repositories" "coordination,repos,integration" 2>/dev/null || true
    fi
}

# Create coordination-aware README template
create_readme_template() {
    cat > "$INTEGRATION_DIR/README.template.md" <<'README'
# {{REPO_NAME}}

{{DESCRIPTION}}

## 🌌 BlackRoad Coordination

This repository is integrated with **BlackRoad Coordination v2.0**!

### Features
- ✅ Automatic conflict detection
- ✅ Real-time activity logging
- ✅ Dependency tracking
- ✅ Performance monitoring

### For Claude Instances
Before working on this repo:
```bash
# Check for conflicts
~/blackroad-conflict-detector.sh check {{REPO_NAME}}

# Claim work
~/blackroad-conflict-detector.sh claim {{REPO_NAME}} "Your task description"

# When done
~/blackroad-conflict-detector.sh release {{REPO_NAME}}
```

## Installation

{{INSTALL_INSTRUCTIONS}}

## Usage

{{USAGE_INSTRUCTIONS}}

## Development

### Setup
```bash
# Install dependencies
{{INSTALL_COMMAND}}

# Run tests
{{TEST_COMMAND}}
```

### Coordination
This repo uses BlackRoad coordination hooks:
- **Pre-commit**: Checks for conflicts with other Claude instances
- **Post-commit**: Logs commits to coordination systems
- **Post-checkout**: Updates local coordination data

## Contributing

All contributions are tracked via BlackRoad Coordination system.

## License

{{LICENSE}}
README

    echo -e "${GREEN}[REPO-INTEGRATION]${NC} README template created!"
}

# Generate enhanced README for a repo
generate_readme() {
    local repo_path="$1"
    local repo_name=$(basename "$repo_path")

    echo -e "${CYAN}  Generating README for: $repo_name${NC}"

    # Detect language and framework
    local language="Unknown"
    local install_cmd="npm install"
    local test_cmd="npm test"

    if [ -f "$repo_path/package.json" ]; then
        language="JavaScript/TypeScript"
    elif [ -f "$repo_path/requirements.txt" ]; then
        language="Python"
        install_cmd="pip install -r requirements.txt"
        test_cmd="pytest"
    elif [ -f "$repo_path/go.mod" ]; then
        language="Go"
        install_cmd="go mod download"
        test_cmd="go test ./..."
    fi

    # Get description from git or package.json
    local description="A BlackRoad project"
    if [ -f "$repo_path/package.json" ]; then
        description=$(jq -r '.description // "A BlackRoad project"' "$repo_path/package.json" 2>/dev/null)
    fi

    # Generate README
    sed -e "s/{{REPO_NAME}}/$repo_name/g" \
        -e "s/{{DESCRIPTION}}/$description/g" \
        -e "s/{{INSTALL_COMMAND}}/$install_cmd/g" \
        -e "s/{{TEST_COMMAND}}/$test_cmd/g" \
        -e "s/{{INSTALL_INSTRUCTIONS}}/See Development section below/g" \
        -e "s/{{USAGE_INSTRUCTIONS}}/See documentation/g" \
        -e "s/{{LICENSE}}/MIT/g" \
        "$INTEGRATION_DIR/README.template.md" > "$repo_path/README-COORDINATION.md"

    echo -e "${GREEN}    ✓${NC} README generated!"
}

# Generate READMEs for all repos
generate_all_readmes() {
    echo -e "${BLUE}[REPO-INTEGRATION]${NC} Generating coordination READMEs for all repositories..."
    echo ""

    if [ -d ~/projects ]; then
        find ~/projects -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            generate_readme "$repo_path"
        done
    fi

    echo ""
    echo -e "${GREEN}[REPO-INTEGRATION]${NC} README generation complete!"
}

# Create CI/CD integration template
create_cicd_template() {
    cat > "$INTEGRATION_DIR/github-workflow.yml" <<'WORKFLOW'
name: BlackRoad Coordination CI

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]

jobs:
  coordination-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Check coordination status
        run: |
          echo "🔍 Checking BlackRoad coordination..."
          if [ -f .blackroad-config.json ]; then
            echo "✅ Coordination enabled"
            cat .blackroad-config.json
          else
            echo "⚠️  Coordination not configured"
          fi

      - name: Validate dependencies
        run: |
          echo "📦 Validating dependencies..."
          # Add dependency checks here

      - name: Run tests
        run: |
          echo "🧪 Running tests..."
          # Add test commands here

      - name: Update coordination systems
        if: success()
        run: |
          echo "📝 Updating coordination systems..."
          # Webhook to update BlackRoad systems
WORKFLOW

    echo -e "${GREEN}[REPO-INTEGRATION]${NC} CI/CD template created!"
}

# Scan all repos and report status
scan_repos() {
    echo -e "${BLUE}[REPO-INTEGRATION]${NC} Scanning all repositories..."
    echo ""

    local total=0
    local integrated=0
    local not_integrated=0

    if [ -d ~/projects ]; then
        echo -e "${CYAN}Repository Status:${NC}"
        echo ""

        find ~/projects -name ".git" -type d 2>/dev/null | while read -r git_dir; do
            local repo_path=$(dirname "$git_dir")
            local repo_name=$(basename "$repo_path")
            ((total++))

            if [ -f "$repo_path/.blackroad-config.json" ]; then
                echo -e "  ${GREEN}✓${NC} $repo_name (integrated)"
                ((integrated++))
            else
                echo -e "  ${YELLOW}○${NC} $repo_name (not integrated)"
                ((not_integrated++))
            fi
        done

        echo ""
        echo -e "${CYAN}Summary:${NC}"
        echo -e "  Total repos: $total"
        echo -e "  Integrated: ${GREEN}$integrated${NC}"
        echo -e "  Not integrated: ${YELLOW}$not_integrated${NC}"
    else
        echo -e "${YELLOW}No projects directory found${NC}"
    fi
}

# Show help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Repository Integration Framework${NC}

Makes EVERY repository coordination-aware!

USAGE:
    blackroad-repo-integration.sh <command>

COMMANDS:
    init                Initialize integration framework
    create-hooks        Create git hooks templates
    install <repo>      Install hooks in specific repo
    install-all         Install hooks in ALL repos
    create-readme       Create README template
    generate-readme <repo>  Generate README for repo
    generate-all-readmes    Generate READMEs for all repos
    create-cicd         Create CI/CD template
    scan                Scan all repos for integration status
    help                Show this help

EXAMPLES:
    # Initialize framework
    blackroad-repo-integration.sh init

    # Create hook templates
    blackroad-repo-integration.sh create-hooks

    # Install in all repos
    blackroad-repo-integration.sh install-all

    # Generate READMEs
    blackroad-repo-integration.sh generate-all-readmes

    # Scan status
    blackroad-repo-integration.sh scan

WHAT IT ADDS TO EACH REPO:
    ✓ Git hooks (pre-commit, post-commit, post-checkout)
    ✓ Coordination config (.blackroad-config.json)
    ✓ Enhanced README (README-COORDINATION.md)
    ✓ CI/CD integration templates
    ✓ Automatic conflict detection
    ✓ Activity logging
    ✓ Performance tracking

HOOKS:
    Templates: $HOOKS_TEMPLATE_DIR
    Config: .blackroad-config.json (per repo)
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_integration
            ;;
        create-hooks)
            create_hooks_template
            ;;
        install)
            if [ -z "$2" ]; then
                echo -e "${RED}[REPO-INTEGRATION]${NC} Repository path required"
                exit 1
            fi
            install_hooks "$2"
            ;;
        install-all)
            create_hooks_template
            install_in_all_repos
            ;;
        create-readme)
            create_readme_template
            ;;
        generate-readme)
            if [ -z "$2" ]; then
                echo -e "${RED}[REPO-INTEGRATION]${NC} Repository path required"
                exit 1
            fi
            create_readme_template
            generate_readme "$2"
            ;;
        generate-all-readmes)
            create_readme_template
            generate_all_readmes
            ;;
        create-cicd)
            create_cicd_template
            ;;
        scan)
            scan_repos
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[REPO-INTEGRATION]${NC} Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
