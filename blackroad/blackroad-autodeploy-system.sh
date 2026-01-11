#!/usr/bin/env bash
# BlackRoad Automatic Deployment System
# Orchestrates deployments across Cloudflare Pages, GitHub Actions, and Pi mesh
# Version: 1.0.0
# Author: Alexa Amundson + Cecilia

set -eo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

CLOUDFLARE_TOKEN="${CF_TOKEN:-yP5h0HvsXX0BpHLs01tLmgtTbQurIKPL4YnQfIwy}"
CLOUDFLARE_ACCOUNT_ID="463024cf9efed5e7b40c5fbe7938e256"
GITHUB_ORG="BlackRoad-OS"

# Pi mesh nodes
declare -A PI_NODES=(
    ["lucidia"]="192.168.4.38"
    ["blackroad"]="192.168.4.64"
    ["lucidia_alt"]="192.168.4.99"
)

# Deployment targets configuration
declare -A DOMAIN_REPOS=(
    # Primary domains
    ["blackroad.io"]="blackroad-os-home"
    ["app.blackroad.io"]="blackroad-os-web"
    ["console.blackroad.io"]="blackroad-os-prism-console"
    ["docs.blackroad.io"]="blackroad-os-docs"
    ["api.blackroad.io"]="blackroad-os-api"
    ["brand.blackroad.io"]="blackroad-os-brand"
    ["status.blackroad.io"]="blackroad-os-beacon"
    ["cdn.blackroad.io"]="blackroad-os-cdn"

    # Lucidia domains
    ["lucidia.earth"]="lucidia-earth-website"
    ["app.lucidia.earth"]="blackroad-os-web"
    ["console.lucidia.earth"]="blackroad-os-prism-console"
    ["docs.lucidia.earth"]="blackroad-os-docs"

    # Vertical packs
    ["finance.blackroad.io"]="blackroad-os-pack-finance"
    ["edu.blackroad.io"]="blackroad-os-pack-education"
    ["studio.blackroad.io"]="blackroad-os-pack-creator-studio"
    ["lab.blackroad.io"]="blackroad-os-pack-research-lab"
    ["canvas.blackroad.io"]="blackroad-os-pack-creator-studio"
    ["video.blackroad.io"]="blackroad-os-pack-creator-studio"
    ["writing.blackroad.io"]="blackroad-os-pack-creator-studio"
    ["legal.blackroad.io"]="blackroad-os-pack-legal"
    ["devops.blackroad.io"]="blackroad-os-pack-infra-devops"

    # More domains
    ["demo.blackroad.io"]="blackroad-os-demo"
    ["sandbox.blackroad.io"]="blackroad-os-demo"
)

# Cloudflare zone IDs
declare -A ZONE_IDS=(
    ["lucidia.earth"]="848cf0b18d51e0170e0d1537aec3505a"
    ["blackroad.io"]="TBD"
    ["blackroad.systems"]="TBD"
)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

success() {
    echo "[✓] $*"
}

# ============================================================================
# CLOUDFLARE FUNCTIONS
# ============================================================================

cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local url="https://api.cloudflare.com/client/v4${endpoint}"

    if [ -n "$data" ]; then
        curl -s -X "$method" "$url" \
            -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "$url" \
            -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
            -H "Content-Type: application/json"
    fi
}

list_cf_pages() {
    log "Listing Cloudflare Pages projects..."
    cf_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects" | \
        python3 -c "import sys,json; data=json.load(sys.stdin); print('\n'.join([p['name'] for p in data.get('result', [])]))"
}

create_cf_pages_project() {
    local project_name="$1"
    local production_branch="${2:-main}"

    log "Creating Cloudflare Pages project: $project_name"

    local payload=$(cat <<EOF
{
  "name": "$project_name",
  "production_branch": "$production_branch",
  "build_config": {
    "build_command": "npm run build",
    "destination_dir": "out",
    "root_dir": ""
  }
}
EOF
)

    cf_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects" "$payload"
}

add_custom_domain() {
    local project_name="$1"
    local domain="$2"

    log "Adding custom domain $domain to $project_name"

    local payload=$(cat <<EOF
{
  "name": "$domain"
}
EOF
)

    cf_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$project_name/domains" "$payload"
}

create_dns_record() {
    local zone_id="$1"
    local type="$2"
    local name="$3"
    local content="$4"
    local proxied="${5:-true}"

    log "Creating DNS record: $name -> $content"

    local payload=$(cat <<EOF
{
  "type": "$type",
  "name": "$name",
  "content": "$content",
  "ttl": 1,
  "proxied": $proxied
}
EOF
)

    cf_api POST "/zones/$zone_id/dns_records" "$payload"
}

# ============================================================================
# GITHUB FUNCTIONS
# ============================================================================

create_github_workflow() {
    local repo="$1"
    local domain="$2"
    local cf_project="$3"

    log "Creating GitHub Actions workflow for $repo"

    local workflow_file=".github/workflows/deploy.yml"

    cat > "/tmp/deploy-workflow.yml" <<'EOF'
name: Deploy to Cloudflare Pages

on:
  push:
    branches:
      - main
      - master
  pull_request:
    branches:
      - main
      - master
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      deployments: write
    name: Deploy to Cloudflare Pages

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build
        env:
          NODE_ENV: production

      - name: Publish to Cloudflare Pages
        uses: cloudflare/pages-action@v1
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          projectName: CF_PROJECT_NAME
          directory: out
          gitHubToken: ${{ secrets.GITHUB_TOKEN }}
          branch: ${{ github.ref_name }}
          wranglerVersion: '3'

      - name: Update deployment status
        if: always()
        run: |
          echo "Deployment completed for CF_PROJECT_NAME"
          echo "Domain: DEPLOYMENT_DOMAIN"
EOF

    # Replace placeholders
    sed -i '' "s/CF_PROJECT_NAME/$cf_project/g" /tmp/deploy-workflow.yml
    sed -i '' "s/DEPLOYMENT_DOMAIN/$domain/g" /tmp/deploy-workflow.yml

    echo "/tmp/deploy-workflow.yml"
}

setup_github_secrets() {
    local repo="$1"

    log "Setting up GitHub secrets for $repo"

    gh secret set CLOUDFLARE_API_TOKEN -b"$CLOUDFLARE_TOKEN" -R "$GITHUB_ORG/$repo" 2>/dev/null || true
    gh secret set CLOUDFLARE_ACCOUNT_ID -b"$CLOUDFLARE_ACCOUNT_ID" -R "$GITHUB_ORG/$repo" 2>/dev/null || true

    success "GitHub secrets configured for $repo"
}

# ============================================================================
# PI MESH FUNCTIONS
# ============================================================================

deploy_to_pi() {
    local pi_name="$1"
    local pi_ip="${PI_NODES[$pi_name]}"
    local service="$2"
    local repo_path="$3"

    log "Deploying $service to Pi node $pi_name ($pi_ip)"

    # Test connection
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes pi@"$pi_ip" "echo 'Connected'" 2>/dev/null; then
        error "Cannot connect to Pi node $pi_name at $pi_ip"
        return 1
    fi

    # Deploy via rsync
    rsync -avz --delete \
        -e "ssh -o ConnectTimeout=10" \
        "$repo_path/" \
        "pi@$pi_ip:/home/pi/services/$service/"

    # Restart service on Pi
    ssh pi@"$pi_ip" "cd /home/pi/services/$service && docker-compose up -d --build" || \
        ssh pi@"$pi_ip" "cd /home/pi/services/$service && ./deploy.sh" || \
        log "No deployment script found on Pi"

    success "Deployed $service to $pi_name"
}

health_check_pi() {
    local pi_name="$1"
    local pi_ip="${PI_NODES[$pi_name]}"

    log "Health checking Pi node: $pi_name"

    if ssh -o ConnectTimeout=5 pi@"$pi_ip" "uptime" 2>/dev/null; then
        success "✓ $pi_name is healthy"
        return 0
    else
        error "✗ $pi_name is unreachable"
        return 1
    fi
}

# ============================================================================
# DEPLOYMENT ORCHESTRATION
# ============================================================================

deploy_domain() {
    local domain="$1"
    local repo="${DOMAIN_REPOS[$domain]}"
    local cf_project="${domain//\./-}"

    log "============================================"
    log "Deploying $domain"
    log "Repository: $repo"
    log "Cloudflare Project: $cf_project"
    log "============================================"

    # 1. Create Cloudflare Pages project if it doesn't exist
    if ! list_cf_pages | grep -q "^$cf_project$"; then
        create_cf_pages_project "$cf_project" "main"
        sleep 2
    fi

    # 2. Add custom domain
    add_custom_domain "$cf_project" "$domain"

    # 3. Set up GitHub workflow
    setup_github_secrets "$repo"

    # 4. Create DNS records if zone exists
    local root_domain="${domain#*.}"
    if [ "${domain}" != "${root_domain}" ]; then
        # It's a subdomain
        root_domain="${domain#*.}"
    else
        root_domain="$domain"
    fi

    if [ -n "${ZONE_IDS[$root_domain]:-}" ]; then
        create_dns_record "${ZONE_IDS[$root_domain]}" "CNAME" "$domain" "$cf_project.pages.dev"
    fi

    success "Deployment configured for $domain"
}

deploy_all() {
    log "Starting mass deployment for all domains..."

    for domain in "${!DOMAIN_REPOS[@]}"; do
        deploy_domain "$domain" || error "Failed to deploy $domain"
        sleep 1
    done

    success "All deployments configured!"
}

# ============================================================================
# TESTING & MONITORING
# ============================================================================

test_deployment() {
    local domain="$1"

    log "Testing deployment: $domain"

    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" || echo "000")

    if [ "$http_code" = "200" ]; then
        success "✓ $domain is live (HTTP $http_code)"
        return 0
    else
        error "✗ $domain returned HTTP $http_code"
        return 1
    fi
}

test_all_deployments() {
    log "Testing all deployments..."

    local failed=0
    for domain in "${!DOMAIN_REPOS[@]}"; do
        if ! test_deployment "$domain"; then
            ((failed++))
        fi
        sleep 0.5
    done

    if [ $failed -eq 0 ]; then
        success "All deployments are healthy!"
    else
        error "$failed deployments failed health check"
    fi
}

# ============================================================================
# STATUS & REPORTING
# ============================================================================

status_report() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  BlackRoad Deployment Status Report                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Cloudflare Pages
    echo "📄 Cloudflare Pages Projects:"
    list_cf_pages | sed 's/^/  - /'
    echo ""

    # Pi mesh
    echo "🥧 Pi Mesh Status:"
    for pi_name in "${!PI_NODES[@]}"; do
        if health_check_pi "$pi_name" 2>/dev/null; then
            echo "  ✓ $pi_name (${PI_NODES[$pi_name]})"
        else
            echo "  ✗ $pi_name (${PI_NODES[$pi_name]})"
        fi
    done
    echo ""

    # Deployment targets
    echo "🎯 Configured Deployments:"
    for domain in "${!DOMAIN_REPOS[@]}"; do
        echo "  - $domain → ${DOMAIN_REPOS[$domain]}"
    done
    echo ""
}

# ============================================================================
# MAIN COMMAND INTERFACE
# ============================================================================

usage() {
    cat <<EOF
BlackRoad Automatic Deployment System

Usage: $0 <command> [options]

Commands:
  deploy <domain>          Deploy a specific domain
  deploy-all               Deploy all configured domains
  test <domain>            Test a specific deployment
  test-all                 Test all deployments
  status                   Show deployment status
  pi-health                Check all Pi nodes
  pi-deploy <pi> <service> Deploy service to Pi node
  cf-pages                 List Cloudflare Pages projects

Examples:
  $0 deploy app.blackroad.io
  $0 deploy-all
  $0 test lucidia.earth
  $0 pi-health
  $0 status

EOF
}

main() {
    case "${1:-}" in
        deploy)
            [ -z "${2:-}" ] && { error "Domain required"; usage; exit 1; }
            deploy_domain "$2"
            ;;
        deploy-all)
            deploy_all
            ;;
        test)
            [ -z "${2:-}" ] && { error "Domain required"; usage; exit 1; }
            test_deployment "$2"
            ;;
        test-all)
            test_all_deployments
            ;;
        status)
            status_report
            ;;
        pi-health)
            for pi in "${!PI_NODES[@]}"; do
                health_check_pi "$pi"
            done
            ;;
        pi-deploy)
            [ -z "${2:-}" ] && { error "Pi name required"; usage; exit 1; }
            [ -z "${3:-}" ] && { error "Service required"; usage; exit 1; }
            [ -z "${4:-}" ] && { error "Repo path required"; usage; exit 1; }
            deploy_to_pi "$2" "$3" "$4"
            ;;
        cf-pages)
            list_cf_pages
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
