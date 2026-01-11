#!/bin/bash
# BlackRoad Hugging Face Deployer
# Deploy models, datasets, and spaces to Hugging Face

set -e

HF_ORG="blackroad"
PRODUCTS_DIR=~/blackroad-products
DB_FILE=~/hf-deployer.db

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize database
init_db() {
    sqlite3 "$DB_FILE" <<SQL
CREATE TABLE IF NOT EXISTS hf_deployments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    product_name TEXT NOT NULL,
    repo_type TEXT NOT NULL,  -- model, dataset, space
    repo_name TEXT NOT NULL,
    hf_url TEXT,
    deployed_at INTEGER,
    status TEXT DEFAULT 'pending',
    UNIQUE(product_name, repo_type)
);
SQL
    echo "✅ Database initialized"
}

# Check if huggingface-cli is installed
check_hf_cli() {
    if ! command -v huggingface-cli &> /dev/null; then
        echo "❌ huggingface-cli not found. Installing..."
        pip3 install huggingface_hub
    fi
    echo "✅ huggingface-cli ready"
}

# Login to Hugging Face
hf_login() {
    echo "🔐 Checking Hugging Face authentication..."
    
    if huggingface-cli whoami &> /dev/null; then
        echo "✅ Already logged in to Hugging Face"
        return 0
    fi
    
    echo "⚠️  Not logged in to Hugging Face"
    echo "Please run: huggingface-cli login"
    echo "Get your token from: https://huggingface.co/settings/tokens"
    return 1
}

# Create a model repository
create_model_repo() {
    local product_name="$1"
    local repo_name="$HF_ORG/$product_name"
    
    echo "📦 Creating model repo: $repo_name"
    
    if huggingface-cli repo create "$product_name" --type model --organization "$HF_ORG" 2>&1 | grep -q "already exists"; then
        echo "  ℹ️  Repo already exists"
    else
        echo "  ✅ Repo created"
    fi
    
    # Record in database
    sqlite3 "$DB_FILE" <<SQL
INSERT OR REPLACE INTO hf_deployments (product_name, repo_type, repo_name, hf_url, deployed_at, status)
VALUES ('$product_name', 'model', '$repo_name', 'https://huggingface.co/$repo_name', $(date +%s), 'created');
SQL
    
    echo "  🌐 https://huggingface.co/$repo_name"
}

# Create a Space
create_space() {
    local product_name="$1"
    local repo_name="$HF_ORG/$product_name"
    
    echo "🚀 Creating Space: $repo_name"
    
    if huggingface-cli repo create "$product_name" --type space --organization "$HF_ORG" --space-sdk static 2>&1 | grep -q "already exists"; then
        echo "  ℹ️  Space already exists"
    else
        echo "  ✅ Space created"
    fi
    
    # Record in database
    sqlite3 "$DB_FILE" <<SQL
INSERT OR REPLACE INTO hf_deployments (product_name, repo_type, repo_name, hf_url, deployed_at, status)
VALUES ('$product_name', 'space', '$repo_name', 'https://huggingface.co/spaces/$repo_name', $(date +%s), 'created');
SQL
    
    echo "  🌐 https://huggingface.co/spaces/$repo_name"
}

# Deploy all products as Spaces (for web apps)
deploy_all_spaces() {
    echo "🚀 Deploying BlackRoad products as Hugging Face Spaces..."
    
    # Get all bash tools
    local count=0
    for script in "$PRODUCTS_DIR"/blackroad-*.sh; do
        [ -f "$script" ] || continue
        [[ "$(basename "$script")" == *"batch-create"* ]] && continue
        
        local filename=$(basename "$script" .sh)
        create_space "$filename"
        count=$((count + 1))
        
        # Rate limiting
        [ $((count % 10)) -eq 0 ] && sleep 5
    done
    
    echo "✅ Created $count Hugging Face Spaces"
}

# Show deployment status
show_status() {
    echo "📊 Hugging Face Deployment Status"
    echo "=================================="
    
    sqlite3 "$DB_FILE" <<SQL
.mode column
.headers on
SELECT 
    repo_type,
    COUNT(*) as count,
    status
FROM hf_deployments
GROUP BY repo_type, status;
SQL
    
    echo ""
    echo "Recent deployments:"
    sqlite3 "$DB_FILE" <<SQL
.mode column
.headers on
SELECT 
    product_name,
    repo_type,
    hf_url
FROM hf_deployments
ORDER BY deployed_at DESC
LIMIT 10;
SQL
}

# Main
case "${1:-help}" in
    init)
        check_hf_cli
        init_db
        hf_login
        ;;
    login)
        hf_login
        ;;
    deploy-spaces)
        deploy_all_spaces
        ;;
    create-model)
        create_model_repo "$2"
        ;;
    create-space)
        create_space "$2"
        ;;
    status)
        show_status
        ;;
    help|*)
        echo "BlackRoad Hugging Face Deployer"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  init              Initialize and login to HF"
        echo "  login             Login to Hugging Face"
        echo "  deploy-spaces     Deploy all products as Spaces"
        echo "  create-model NAME Create a model repo"
        echo "  create-space NAME Create a Space"
        echo "  status            Show deployment status"
        ;;
esac
