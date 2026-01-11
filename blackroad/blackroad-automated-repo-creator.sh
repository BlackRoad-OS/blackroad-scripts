#!/bin/bash
# BlackRoad Automated GitHub Repo Creator
# One-command repo creation for any product

set -e

ORG="${BLACKROAD_ORG:-BlackRoad-OS}"
DEFAULT_LICENSE="MIT"
DEFAULT_VISIBILITY="public"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

create_repo() {
    local repo_name="$1"
    local description="${2:-BlackRoad product}"
    local license="${3:-$DEFAULT_LICENSE}"
    local visibility="${4:-$DEFAULT_VISIBILITY}"
    
    echo "📦 Creating repository: $ORG/$repo_name"
    
    # Create staging directory
    local staging_dir="/tmp/blackroad-repo-creator/$repo_name"
    rm -rf "$staging_dir"
    mkdir -p "$staging_dir"
    
    # Create README
    cat > "$staging_dir/README.md" << ENDREADME
# $repo_name

$description

Part of the BlackRoad Product Suite - 150+ tools for modern development.

## Installation

\`\`\`bash
# Clone the repository
git clone https://github.com/$ORG/$repo_name.git
cd $repo_name

# Install dependencies (if applicable)
npm install  # or pip install -r requirements.txt

# Run
npm start    # or python main.py
\`\`\`

## Features

- 🚀 Fast and efficient
- 🎨 BlackRoad design system
- 🔒 Secure by default
- 📦 Easy to integrate

## Documentation

See [docs/](./docs/) for detailed documentation.

## Contributing

Contributions welcome! Please read our [Contributing Guide](CONTRIBUTING.md) first.

## License

$license License - see [LICENSE](LICENSE) for details.

## About BlackRoad

BlackRoad OS is building the future of development tools and infrastructure.

🖤🛣️ **Built with BlackRoad**

- Website: https://blackroad.io
- GitHub: https://github.com/$ORG
- Twitter: @BlackRoadOS
ENDREADME
    
    # Create LICENSE
    if [ "$license" = "MIT" ]; then
        cat > "$staging_dir/LICENSE" << ENDLICENSE
MIT License

Copyright (c) 2026 BlackRoad OS, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
ENDLICENSE
    fi
    
    # Create CONTRIBUTING.md
    cat > "$staging_dir/CONTRIBUTING.md" << 'ENDCONTRIB'
# Contributing to BlackRoad

Thank you for your interest in contributing!

## Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Code Style

- Follow existing code style
- Add tests for new features
- Update documentation as needed

## Questions?

Open an issue or reach out to blackroad.systems@gmail.com
ENDCONTRIB
    
    # Create .gitignore
    cat > "$staging_dir/.gitignore" << 'ENDIGNORE'
# Dependencies
node_modules/
vendor/
__pycache__/
*.pyc
.venv/
venv/

# Build outputs
dist/
build/
*.o
*.so
*.dylib

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Env files
.env
.env.local
*.key
*.pem

# Logs
*.log
logs/
ENDIGNORE
    
    # Initialize git
    cd "$staging_dir"
    git init -b main > /dev/null 2>&1
    git add . > /dev/null 2>&1
    git commit -m "Initial commit: $repo_name" > /dev/null 2>&1
    
    # Create GitHub repo and push
    if gh repo create "$ORG/$repo_name" \
        --description "$description" \
        --${visibility} \
        --source=. \
        --remote=origin \
        --push 2>&1 | tee /tmp/repo-creation-$repo_name.log; then
        
        echo "  ✅ Repository created successfully!"
        echo "  🌐 https://github.com/$ORG/$repo_name"
        return 0
    else
        if grep -q "already exists" /tmp/repo-creation-$repo_name.log; then
            echo "  ℹ️  Repository already exists"
            return 0
        else
            echo "  ❌ Failed to create repository"
            return 1
        fi
    fi
}

# Batch create from CSV
batch_create() {
    local csv_file="$1"
    
    if [ ! -f "$csv_file" ]; then
        echo "❌ CSV file not found: $csv_file"
        return 1
    fi
    
    echo "📦 Batch creating repositories from $csv_file"
    echo ""
    
    local count=0
    local success=0
    
    while IFS=',' read -r name description license visibility; do
        # Skip header
        [ "$name" = "name" ] && continue
        
        count=$((count + 1))
        
        if create_repo "$name" "$description" "$license" "$visibility"; then
            success=$((success + 1))
        fi
        
        echo ""
        
        # Rate limiting
        [ $((count % 5)) -eq 0 ] && sleep 3
    done < "$csv_file"
    
    echo "✅ Batch creation complete!"
    echo "📊 Created $success out of $count repositories"
}

# Quick create (interactive)
quick_create() {
    echo "🚀 BlackRoad Automated Repo Creator"
    echo "===================================="
    echo ""
    
    read -p "Repository name: " repo_name
    read -p "Description: " description
    read -p "License (MIT): " license
    license=${license:-MIT}
    read -p "Visibility (public): " visibility
    visibility=${visibility:-public}
    
    echo ""
    create_repo "$repo_name" "$description" "$license" "$visibility"
}

# Main
case "${1:-help}" in
    create)
        create_repo "$2" "$3" "$4" "$5"
        ;;
    batch)
        batch_create "$2"
        ;;
    quick)
        quick_create
        ;;
    help|*)
        echo "BlackRoad Automated GitHub Repo Creator"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <name> <desc> [license] [visibility]"
        echo "                    Create a single repository"
        echo ""
        echo "  batch <csv-file>  Create multiple repos from CSV"
        echo "                    Format: name,description,license,visibility"
        echo ""
        echo "  quick             Interactive mode"
        echo ""
        echo "Examples:"
        echo "  $0 create blackroad-app 'My app' MIT public"
        echo "  $0 batch repos.csv"
        echo "  $0 quick"
        ;;
esac
