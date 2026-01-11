#!/usr/bin/env bash
# BlackRoad Webhook Receiver
# Receives deployment commands from Cloudflare Worker
# Executes role-based deployments
# Version: 1.0.0

set -euo pipefail

VERSION="1.0.0"
CONFIG_FILE="/opt/blackroad/agent/config.env"
WORKSPACE_DIR="/opt/blackroad/workspace"
REPOS_DIR="$WORKSPACE_DIR/repos"
BUILDS_DIR="$WORKSPACE_DIR/builds"
LOGS_DIR="$WORKSPACE_DIR/logs"
SCRIPTS_DIR="/opt/blackroad/scripts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️  Config not found, using defaults"
    NODE_NAME="${HOSTNAME:-unknown}"
    NODE_ROLE="${NODE_ROLE:-generic}"
    WEBHOOK_PORT="${WEBHOOK_PORT:-9001}"
    WEBHOOK_SECRET="${WEBHOOK_SECRET:-changeme}"
fi

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" | tee -a "$LOGS_DIR/webhook.log"
}

verify_secret() {
    local provided_secret="$1"
    if [[ "$provided_secret" != "$WEBHOOK_SECRET" ]]; then
        log "ERROR" "Invalid webhook secret"
        return 1
    fi
    return 0
}

handle_deployment() {
    local payload="$1"

    # Parse JSON payload (requires jq)
    local repo=$(echo "$payload" | jq -r '.repository')
    local branch=$(echo "$payload" | jq -r '.branch')
    local commit=$(echo "$payload" | jq -r '.commit')
    local task=$(echo "$payload" | jq -r '.task // "deploy"')

    log "INFO" "Received deployment: repo=$repo branch=$branch commit=$commit task=$task"

    # Clone or update repo
    local repo_path="$REPOS_DIR/$(basename "$repo" .git)"

    if [[ ! -d "$repo_path" ]]; then
        log "INFO" "Cloning $repo..."
        git clone "https://github.com/$repo.git" "$repo_path" 2>&1 | tee -a "$LOGS_DIR/git.log"
    else
        log "INFO" "Updating $repo..."
        (cd "$repo_path" && git fetch origin && git checkout "$branch" && git pull origin "$branch") 2>&1 | tee -a "$LOGS_DIR/git.log"
    fi

    # Create build directory for this commit
    local build_dir="$BUILDS_DIR/$commit"
    mkdir -p "$build_dir"

    # Execute role-based deployment script
    local deploy_script="$SCRIPTS_DIR/deploy-${NODE_ROLE}.sh"

    if [[ -f "$deploy_script" ]]; then
        log "INFO" "Executing $deploy_script..."

        export REPO_PATH="$repo_path"
        export BUILD_DIR="$build_dir"
        export COMMIT="$commit"
        export BRANCH="$branch"
        export TASK="$task"

        if bash "$deploy_script" 2>&1 | tee "$build_dir/deploy.log"; then
            log "INFO" "Deployment succeeded"
            echo "success" > "$build_dir/status"
            return 0
        else
            log "ERROR" "Deployment failed"
            echo "failed" > "$build_dir/status"
            return 1
        fi
    else
        log "WARN" "No deployment script for role $NODE_ROLE"
        echo "skipped" > "$build_dir/status"
        return 0
    fi
}

http_response() {
    local status="$1"
    local body="$2"

    echo "HTTP/1.1 $status"
    echo "Content-Type: application/json"
    echo "Content-Length: ${#body}"
    echo "Connection: close"
    echo ""
    echo "$body"
}

handle_request() {
    local request_line
    read -r request_line

    local method=$(echo "$request_line" | awk '{print $1}')
    local path=$(echo "$request_line" | awk '{print $2}')

    # Read headers
    local content_length=0
    local secret_header=""

    while IFS=': ' read -r key value; do
        value=$(echo "$value" | tr -d '\r\n')
        case "$key" in
            Content-Length)
                content_length=$value
                ;;
            X-Webhook-Secret)
                secret_header=$value
                ;;
        esac

        # Empty line marks end of headers
        [[ -z "$key" ]] && break
    done

    case "$path" in
        /health)
            # Health check endpoint
            local disk_usage=$(df -h / | tail -1 | awk '{print $5}')
            local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
            local response=$(jq -n \
                --arg status "healthy" \
                --arg node "$NODE_NAME" \
                --arg role "$NODE_ROLE" \
                --arg disk "$disk_usage" \
                --arg load "$load_avg" \
                '{status: $status, node: $node, role: $role, disk: $disk, load: $load}')

            http_response "200 OK" "$response"
            ;;

        /deploy)
            # Deployment endpoint
            if [[ "$method" != "POST" ]]; then
                http_response "405 Method Not Allowed" '{"error":"Only POST allowed"}'
                return
            fi

            # Verify secret
            if ! verify_secret "$secret_header"; then
                http_response "403 Forbidden" '{"error":"Invalid secret"}'
                return
            fi

            # Read POST body
            local payload=""
            if [[ $content_length -gt 0 ]]; then
                payload=$(head -c "$content_length")
            fi

            # Handle deployment in background
            (
                if handle_deployment "$payload"; then
                    log "INFO" "Deployment completed successfully"
                else
                    log "ERROR" "Deployment failed"
                fi
            ) &

            # Respond immediately
            http_response "202 Accepted" '{"status":"accepted","message":"Deployment started"}'
            ;;

        *)
            http_response "404 Not Found" '{"error":"Not found"}'
            ;;
    esac
}

start_server() {
    log "INFO" "Starting BlackRoad webhook receiver v$VERSION"
    log "INFO" "Node: $NODE_NAME, Role: $NODE_ROLE, Port: $WEBHOOK_PORT"

    # Create required directories
    mkdir -p "$REPOS_DIR" "$BUILDS_DIR" "$LOGS_DIR"

    # Start server using netcat or socat
    if command -v socat &> /dev/null; then
        log "INFO" "Using socat for HTTP server"
        while true; do
            socat TCP-LISTEN:$WEBHOOK_PORT,reuseaddr,fork SYSTEM:'bash -c "source /opt/blackroad/agent/webhook-receiver.sh && handle_request"' 2>&1 | tee -a "$LOGS_DIR/server.log"
        done
    elif command -v nc &> /dev/null; then
        log "INFO" "Using netcat for HTTP server"
        while true; do
            nc -l -p $WEBHOOK_PORT -c "bash -c 'source /opt/blackroad/agent/webhook-receiver.sh && handle_request'" 2>&1 | tee -a "$LOGS_DIR/server.log"
        done
    else
        log "ERROR" "Neither socat nor netcat available. Install one of them."
        exit 1
    fi
}

install() {
    echo "🔧 Installing BlackRoad webhook receiver..."

    # Create directory structure
    sudo mkdir -p /opt/blackroad/{agent,workspace/{repos,builds,logs},scripts}

    # Copy this script
    sudo cp "$0" /opt/blackroad/agent/webhook-receiver.sh
    sudo chmod +x /opt/blackroad/agent/webhook-receiver.sh

    # Create default config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        sudo tee "$CONFIG_FILE" > /dev/null << EOF
NODE_NAME="$(hostname)"
NODE_ROLE="generic"
WEBHOOK_PORT=9001
WEBHOOK_SECRET="$(openssl rand -hex 32)"
EOF
        echo "✅ Created config at $CONFIG_FILE"
        echo "⚠️  Update NODE_ROLE and WEBHOOK_SECRET in $CONFIG_FILE"
    fi

    # Create systemd service
    sudo tee /etc/systemd/system/blackroad-webhook.service > /dev/null << EOF
[Unit]
Description=BlackRoad Webhook Receiver
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/blackroad/agent/webhook-receiver.sh start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload

    echo "✅ Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit /opt/blackroad/agent/config.env with your settings"
    echo "  2. Create deployment scripts in /opt/blackroad/scripts/"
    echo "  3. Start service: sudo systemctl start blackroad-webhook"
    echo "  4. Enable on boot: sudo systemctl enable blackroad-webhook"
}

case "${1:-}" in
    start)
        start_server
        ;;
    install)
        install
        ;;
    test)
        # Test deployment locally
        echo '{"repository":"BlackRoad-OS/test","branch":"main","commit":"abc123","task":"deploy"}' | \
        curl -X POST -H "X-Webhook-Secret: $WEBHOOK_SECRET" -H "Content-Type: application/json" \
        --data @- "http://localhost:$WEBHOOK_PORT/deploy"
        ;;
    *)
        echo "BlackRoad Webhook Receiver v$VERSION"
        echo ""
        echo "Usage: $0 {install|start|test}"
        echo ""
        echo "Commands:"
        echo "  install  - Install as systemd service"
        echo "  start    - Start webhook server"
        echo "  test     - Send test webhook"
        exit 1
        ;;
esac
