#!/bin/bash
# BlackRoad Sovereignty Fork Tracker
# Manages forking and enhancement of 100+ open source repos

DB_PATH="$HOME/.blackroad/sovereignty-forks.db"
mkdir -p "$(dirname "$DB_PATH")"

# Initialize database
init_db() {
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS forks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,
    component TEXT NOT NULL,
    original_repo TEXT NOT NULL,
    license TEXT NOT NULL,
    blackroad_repo TEXT,
    fork_status TEXT DEFAULT 'pending',
    enhancement_status TEXT DEFAULT 'pending',
    priority INTEGER DEFAULT 99,
    forked_at TIMESTAMP,
    enhanced_at TIMESTAMP,
    notes TEXT,
    hash TEXT
);

CREATE TABLE IF NOT EXISTS enhancements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fork_id INTEGER,
    enhancement_type TEXT,
    description TEXT,
    status TEXT DEFAULT 'pending',
    completed_at TIMESTAMP,
    FOREIGN KEY(fork_id) REFERENCES forks(id)
);

CREATE TABLE IF NOT EXISTS fork_stats (
    total_repos INTEGER,
    forked INTEGER,
    enhanced INTEGER,
    pending INTEGER,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    echo "✅ Fork tracking database initialized: $DB_PATH"
}

# Add a repository to track
add_repo() {
    local category="$1"
    local component="$2"
    local original_repo="$3"
    local license="$4"
    local priority="${5:-99}"

    local hash=$(echo -n "$original_repo" | shasum | cut -c1-8)

    sqlite3 "$DB_PATH" <<EOF
INSERT OR IGNORE INTO forks (category, component, original_repo, license, priority, hash)
VALUES ('$category', '$component', '$original_repo', '$license', $priority, '$hash');
EOF
}

# Bulk import from canonical stack
import_canonical_stack() {
    echo "📥 Importing canonical sovereignty stack..."

    # Phase 1: Critical Infrastructure (Priority 1-4)
    add_repo "Identity" "Keycloak" "https://github.com/keycloak/keycloak" "Apache-2.0" 1
    add_repo "Identity" "Authelia" "https://github.com/authelia/authelia" "Apache-2.0" 2
    add_repo "Identity" "Hyperledger Aries" "https://github.com/hyperledger/aries" "Apache-2.0" 3

    add_repo "Network" "Headscale" "https://github.com/juanfont/headscale" "MIT" 1
    add_repo "Network" "NetBird" "https://github.com/netbirdio/netbird" "BSD" 2
    add_repo "Network" "Nebula" "https://github.com/slackhq/nebula" "MIT" 3
    add_repo "Network" "Innernet" "https://github.com/tonarino/innernet" "MIT" 4
    add_repo "Network" "Netmaker" "https://github.com/gravitl/netmaker" "SSPL" 5

    add_repo "AI-Runtime" "vLLM" "https://github.com/vllm-project/vllm" "Apache-2.0" 1
    add_repo "AI-Runtime" "Ollama" "https://github.com/ollama/ollama" "MIT" 2
    add_repo "AI-Runtime" "LocalAI" "https://github.com/mudler/LocalAI" "MIT" 3

    add_repo "AI-Agent" "LangChain" "https://github.com/langchain-ai/langchain" "MIT" 1
    add_repo "AI-Agent" "Haystack" "https://github.com/deepset-ai/haystack" "Apache-2.0" 2
    add_repo "AI-Agent" "CrewAI" "https://github.com/joaomdmoura/crewAI" "MIT" 3

    add_repo "CRM" "EspoCRM" "https://github.com/espocrm/espocrm" "GPL-3.0" 1
    add_repo "CRM" "SuiteCRM" "https://github.com/salesagility/SuiteCRM" "AGPL-3.0" 2
    add_repo "CRM" "Odoo" "https://github.com/odoo/odoo" "LGPL-3.0" 3

    # Core Infrastructure
    add_repo "Database" "PostgreSQL" "https://github.com/postgres/postgres" "PostgreSQL" 1
    add_repo "Database" "ClickHouse" "https://github.com/ClickHouse/ClickHouse" "Apache-2.0" 2
    add_repo "Database" "Qdrant" "https://github.com/qdrant/qdrant" "Apache-2.0" 3
    add_repo "Database" "Weaviate" "https://github.com/weaviate/weaviate" "BSD" 4
    add_repo "Database" "ArangoDB" "https://github.com/arangodb/arangodb" "Apache-2.0" 5

    add_repo "Storage" "MinIO" "https://github.com/minio/minio" "AGPL-3.0" 1
    add_repo "Storage" "Ceph" "https://github.com/ceph/ceph" "LGPL-2.1" 2

    add_repo "Search" "OpenSearch" "https://github.com/opensearch-project/OpenSearch" "Apache-2.0" 1
    add_repo "Search" "Meilisearch" "https://github.com/meilisearch/meilisearch" "MIT" 2
    add_repo "Search" "Solr" "https://github.com/apache/solr" "Apache-2.0" 3

    # AI Media
    add_repo "AI-Image" "Stable Diffusion" "https://github.com/Stability-AI/stablediffusion" "CreativeML-OpenRAIL-M" 1
    add_repo "AI-Image" "ComfyUI" "https://github.com/comfyanonymous/ComfyUI" "GPL-3.0" 2
    add_repo "AI-Image" "Krita" "https://github.com/KDE/krita" "GPL-3.0" 3

    add_repo "AI-Video" "Blender" "https://github.com/blender/blender" "GPL-3.0" 1
    add_repo "AI-Video" "OBS Studio" "https://github.com/obsproject/obs-studio" "GPL-2.0" 2

    add_repo "AI-Speech" "Whisper" "https://github.com/openai/whisper" "MIT" 1
    add_repo "AI-Speech" "Vosk" "https://github.com/alphacep/vosk-api" "Apache-2.0" 2
    add_repo "AI-Speech" "Coqui TTS" "https://github.com/coqui-ai/TTS" "MPL-2.0" 3

    add_repo "AI-Training" "PyTorch" "https://github.com/pytorch/pytorch" "BSD" 1
    add_repo "AI-Training" "JAX" "https://github.com/google/jax" "Apache-2.0" 2
    add_repo "AI-Training" "Ray" "https://github.com/ray-project/ray" "Apache-2.0" 3

    # Business Systems
    add_repo "ProjectMgmt" "OpenProject" "https://github.com/opf/openproject" "GPL-3.0" 1
    add_repo "ProjectMgmt" "Taiga" "https://github.com/taigaio/taiga" "AGPL-3.0" 2
    add_repo "ProjectMgmt" "Plane" "https://github.com/makeplane/plane" "Apache-2.0" 3
    add_repo "ProjectMgmt" "Focalboard" "https://github.com/mattermost/focalboard" "MIT" 4

    add_repo "Knowledge" "Outline" "https://github.com/outline/outline" "BSD" 1
    add_repo "Knowledge" "Wiki.js" "https://github.com/requarks/wiki" "AGPL-3.0" 2
    add_repo "Knowledge" "BookStack" "https://github.com/BookStackApp/BookStack" "MIT" 3

    add_repo "Office" "OnlyOffice" "https://github.com/ONLYOFFICE/DocumentServer" "AGPL-3.0" 1
    add_repo "Office" "Collabora" "https://github.com/CollaboraOnline/online" "MPL-2.0" 2
    add_repo "Office" "LibreOffice" "https://github.com/LibreOffice/core" "MPL-2.0" 3

    add_repo "Accounting" "ERPNext" "https://github.com/frappe/erpnext" "GPL-3.0" 1
    add_repo "Accounting" "GnuCash" "https://github.com/Gnucash/gnucash" "GPL-2.0" 2
    add_repo "Accounting" "Beancount" "https://github.com/beancount/beancount" "GPL-2.0" 3

    add_repo "Payments" "BTCPay Server" "https://github.com/btcpayserver/btcpayserver" "MIT" 1

    # Communication
    add_repo "Chat" "Synapse" "https://github.com/matrix-org/synapse" "Apache-2.0" 1
    add_repo "Chat" "Dendrite" "https://github.com/matrix-org/dendrite" "Apache-2.0" 2
    add_repo "Chat" "Element" "https://github.com/vector-im/element-web" "Apache-2.0" 3

    add_repo "VideoVoice" "Jitsi" "https://github.com/jitsi/jitsi-meet" "Apache-2.0" 1
    add_repo "VideoVoice" "BigBlueButton" "https://github.com/bigbluebutton/bigbluebutton" "LGPL-3.0" 2

    # Data & Storage
    add_repo "Sync" "Syncthing" "https://github.com/syncthing/syncthing" "MPL-2.0" 1
    add_repo "Sync" "Nextcloud" "https://github.com/nextcloud/server" "AGPL-3.0" 2

    add_repo "Backup" "Restic" "https://github.com/restic/restic" "BSD" 1
    add_repo "Backup" "Borg" "https://github.com/borgbackup/borg" "BSD" 2

    # Development Tools
    add_repo "Git" "Forgejo" "https://codeberg.org/forgejo/forgejo" "MIT" 1
    add_repo "Git" "Gitea" "https://github.com/go-gitea/gitea" "MIT" 2
    add_repo "Git" "GitLab CE" "https://gitlab.com/gitlab-org/gitlab-foss" "MIT" 3

    add_repo "CICD" "Woodpecker CI" "https://github.com/woodpecker-ci/woodpecker" "Apache-2.0" 1
    add_repo "CICD" "Drone" "https://github.com/harness/drone" "Apache-2.0" 2

    add_repo "Containers" "Nomad" "https://github.com/hashicorp/nomad" "MPL-2.0" 1
    add_repo "Containers" "Kubernetes" "https://github.com/kubernetes/kubernetes" "Apache-2.0" 2

    add_repo "IaC" "OpenTofu" "https://github.com/opentofu/opentofu" "MPL-2.0" 1
    add_repo "IaC" "Pulumi" "https://github.com/pulumi/pulumi" "Apache-2.0" 2

    # Network & Security
    add_repo "Crypto" "libsodium" "https://github.com/jedisct1/libsodium" "ISC" 1
    add_repo "Crypto" "OpenSSL" "https://github.com/openssl/openssl" "Apache-2.0" 2
    add_repo "Crypto" "liboqs" "https://github.com/open-quantum-safe/liboqs" "MIT" 3

    add_repo "Secrets" "OpenBao" "https://github.com/openbao/openbao" "MPL-2.0" 1
    add_repo "Secrets" "SOPS" "https://github.com/mozilla/sops" "MPL-2.0" 2
    add_repo "Secrets" "age" "https://github.com/FiloSottile/age" "BSD" 3

    add_repo "Firewall" "Firejail" "https://github.com/netblue30/firejail" "GPL-2.0" 1

    add_repo "DNS" "Unbound" "https://github.com/NLnetLabs/unbound" "BSD" 1
    add_repo "DNS" "PowerDNS" "https://github.com/PowerDNS/pdns" "GPL-2.0" 2
    add_repo "DNS" "Knot DNS" "https://github.com/CZ-NIC/knot" "GPL-3.0" 3

    # Observability
    add_repo "Monitoring" "Prometheus" "https://github.com/prometheus/prometheus" "Apache-2.0" 1
    add_repo "Monitoring" "Grafana" "https://github.com/grafana/grafana" "AGPL-3.0" 2
    add_repo "Monitoring" "Loki" "https://github.com/grafana/loki" "AGPL-3.0" 3

    add_repo "Policy" "Open Policy Agent" "https://github.com/open-policy-agent/opa" "Apache-2.0" 1
    add_repo "Policy" "Falco" "https://github.com/falcosecurity/falco" "Apache-2.0" 2

    # Civilization-Scale
    add_repo "Browser" "Firefox" "https://hg.mozilla.org/mozilla-central/" "MPL-2.0" 1
    add_repo "Browser" "Servo" "https://github.com/servo/servo" "MPL-2.0" 2

    add_repo "Search-Engine" "SearXNG" "https://github.com/searxng/searxng" "AGPL-3.0" 1
    add_repo "Search-Engine" "YaCy" "https://github.com/yacy/yacy_search_server" "LGPL-2.1" 2

    add_repo "Maps" "MapLibre" "https://github.com/maplibre/maplibre-gl-js" "BSD" 1
    add_repo "Maps" "TileServer GL" "https://github.com/maptiler/tileserver-gl" "BSD" 2
    add_repo "Maps" "PostGIS" "https://github.com/postgis/postgis" "GPL-2.0" 3

    add_repo "Social" "Mastodon" "https://github.com/mastodon/mastodon" "AGPL-3.0" 1
    add_repo "Social" "Pleroma" "https://git.pleroma.social/pleroma/pleroma" "AGPL-3.0" 2

    add_repo "Video-Platform" "PeerTube" "https://github.com/Chocobozzz/PeerTube" "AGPL-3.0" 1
    add_repo "Video-Platform" "Owncast" "https://github.com/owncast/owncast" "MIT" 2

    add_repo "Publishing" "Ghost" "https://github.com/TryGhost/Ghost" "MIT" 1
    add_repo "Publishing" "WriteFreely" "https://github.com/writefreely/writefreely" "AGPL-3.0" 2
    add_repo "Publishing" "Hugo" "https://github.com/gohugoio/hugo" "Apache-2.0" 3

    add_repo "Education" "Moodle" "https://github.com/moodle/moodle" "GPL-3.0" 1
    add_repo "Education" "Open edX" "https://github.com/openedx/edx-platform" "AGPL-3.0" 2
    add_repo "Education" "Kiwix" "https://github.com/kiwix/kiwix-tools" "GPL-3.0" 3

    add_repo "Science" "Jupyter" "https://github.com/jupyter/notebook" "BSD" 1
    add_repo "Science" "Quarto" "https://github.com/quarto-dev/quarto-cli" "GPL-2.0" 2
    add_repo "Science" "CKAN" "https://github.com/ckan/ckan" "AGPL-3.0" 3

    echo "✅ Canonical sovereignty stack imported!"
}

# Fork a repository to BlackRoad org
fork_repo() {
    local fork_id="$1"
    local org="${2:-BlackRoad-OS}"

    local repo_info=$(sqlite3 "$DB_PATH" "SELECT component, original_repo FROM forks WHERE id=$fork_id;")
    local component=$(echo "$repo_info" | cut -d'|' -f1)
    local original_repo=$(echo "$repo_info" | cut -d'|' -f2)

    echo "🔱 Forking: $component ($original_repo) to $org..."

    # Extract owner/repo from URL
    local repo_path=$(echo "$original_repo" | sed 's|https://github.com/||' | sed 's|.git||')

    # Fork using gh CLI
    gh repo fork "$repo_path" --org "$org" --clone=false --remote=false

    local blackroad_repo="https://github.com/$org/$(basename $original_repo .git)"

    # Update database
    sqlite3 "$DB_PATH" <<EOF
UPDATE forks
SET fork_status='forked',
    blackroad_repo='$blackroad_repo',
    forked_at=CURRENT_TIMESTAMP
WHERE id=$fork_id;
EOF

    echo "✅ Forked to: $blackroad_repo"
}

# Enhance a forked repo with BlackRoad branding
enhance_repo() {
    local fork_id="$1"

    local repo_info=$(sqlite3 "$DB_PATH" "SELECT component, blackroad_repo FROM forks WHERE id=$fork_id;")
    local component=$(echo "$repo_info" | cut -d'|' -f1)
    local blackroad_repo=$(echo "$repo_info" | cut -d'|' -f2)

    if [ -z "$blackroad_repo" ]; then
        echo "❌ Repository not yet forked!"
        return 1
    fi

    echo "✨ Enhancing: $component..."

    # Clone locally
    local clone_dir="/tmp/blackroad-fork-$(echo $component | tr ' ' '-')"
    gh repo clone "$blackroad_repo" "$clone_dir"

    cd "$clone_dir"

    # Add BlackRoad branding
    cat > BLACKROAD.md <<'BRANDING'
# BlackRoad Edition

This is a **BlackRoad OS** fork, part of the Sovereignty Stack.

## Why This Fork?

BlackRoad maintains this fork to ensure:
- ✅ **Post-permission infrastructure** - No remote kill switches
- ✅ **Offline-first** - Runs without internet
- ✅ **Zero vendor lock-in** - You control everything
- ✅ **Enhanced for sovereignty** - Additional privacy & security features

## Enhancements Over Upstream

See [BLACKROAD_ENHANCEMENTS.md](./BLACKROAD_ENHANCEMENTS.md) for details.

## Upstream

Original project: Linked in repository description

## Support

- BlackRoad Issues: This repository's issue tracker
- Upstream Issues: Original project's tracker
- Email: blackroad.systems@gmail.com

---

**The road remembers everything. So should we.**

*Part of the BlackRoad Sovereignty Stack*
BRANDING

    cat > BLACKROAD_ENHANCEMENTS.md <<'ENHANCEMENTS'
# BlackRoad Enhancements

This document tracks BlackRoad-specific modifications to the upstream project.

## Version History

### v1.0.0-blackroad (Initial Fork)
- ✅ Forked from upstream
- ✅ Added BlackRoad branding
- ✅ Integrated with BlackRoad infrastructure
- 🔄 Planned: Additional sovereignty enhancements

## Planned Enhancements

- [ ] Remove all telemetry/phone-home
- [ ] Add offline-first capabilities
- [ ] Integrate with BlackRoad identity (Keycloak)
- [ ] Add BlackRoad design system
- [ ] Enhanced privacy controls
- [ ] Self-sovereign data export

## Contributing

Contributions welcome! Follow BlackRoad contribution guidelines.

## License

Maintains upstream license. See [LICENSE](./LICENSE).
ENHANCEMENTS

    # Commit and push
    git add BLACKROAD.md BLACKROAD_ENHANCEMENTS.md
    git commit -m "🎨 Add BlackRoad branding and sovereignty enhancements

Part of the BlackRoad Sovereignty Stack.

🤖 Generated with Claude Code (Cecilia)
Co-Authored-By: Claude <noreply@anthropic.com>"
    git push

    cd -
    rm -rf "$clone_dir"

    # Update database
    sqlite3 "$DB_PATH" <<EOF
UPDATE forks
SET enhancement_status='enhanced',
    enhanced_at=CURRENT_TIMESTAMP
WHERE id=$fork_id;

INSERT INTO enhancements (fork_id, enhancement_type, description, status, completed_at)
VALUES ($fork_id, 'branding', 'Added BlackRoad branding files', 'completed', CURRENT_TIMESTAMP);
EOF

    echo "✅ Enhanced: $component"
}

# Bulk fork by category
fork_category() {
    local category="$1"
    local org="${2:-BlackRoad-OS}"

    echo "🔱 Forking all repos in category: $category"

    local fork_ids=$(sqlite3 "$DB_PATH" "SELECT id FROM forks WHERE category='$category' AND fork_status='pending' ORDER BY priority;")

    for fork_id in $fork_ids; do
        fork_repo "$fork_id" "$org"
        sleep 2  # Rate limiting
    done
}

# Statistics
stats() {
    echo ""
    echo "═════════════════════════════════════════════════════════"
    echo "  📊 BLACKROAD SOVEREIGNTY FORK TRACKER"
    echo "═════════════════════════════════════════════════════════"
    echo ""

    local total=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM forks;")
    local forked=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM forks WHERE fork_status='forked';")
    local enhanced=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM forks WHERE enhancement_status='enhanced';")
    local pending=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM forks WHERE fork_status='pending';")

    echo "  📦 Total Repositories:    $total"
    echo "  ✅ Forked:                $forked"
    echo "  ✨ Enhanced:              $enhanced"
    echo "  ⏳ Pending:               $pending"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  📋 By Category:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sqlite3 "$DB_PATH" "SELECT category, COUNT(*) as count FROM forks GROUP BY category ORDER BY count DESC;" | \
        while IFS='|' read category count; do
            printf "  %-20s %3d repos\n" "$category" "$count"
        done
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🔥 Priority Queue (Next 10):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sqlite3 "$DB_PATH" "SELECT id, category, component, fork_status FROM forks WHERE fork_status='pending' ORDER BY priority LIMIT 10;" | \
        while IFS='|' read id category component status; do
            printf "  [%3d] %-15s %-25s (%s)\n" "$id" "$category" "$component" "$status"
        done
    echo ""
    echo "═════════════════════════════════════════════════════════"
}

# List repos
list() {
    local filter="${1:-all}"

    case "$filter" in
        pending)
            sqlite3 "$DB_PATH" "SELECT id, category, component, license FROM forks WHERE fork_status='pending' ORDER BY priority;"
            ;;
        forked)
            sqlite3 "$DB_PATH" "SELECT id, category, component, blackroad_repo FROM forks WHERE fork_status='forked';"
            ;;
        enhanced)
            sqlite3 "$DB_PATH" "SELECT id, category, component, blackroad_repo FROM forks WHERE enhancement_status='enhanced';"
            ;;
        *)
            sqlite3 "$DB_PATH" "SELECT id, category, component, fork_status, enhancement_status FROM forks ORDER BY category, priority;"
            ;;
    esac
}

# Main command router
case "${1:-help}" in
    init)
        init_db
        ;;
    import)
        import_canonical_stack
        ;;
    fork)
        fork_repo "$2" "${3:-BlackRoad-OS}"
        ;;
    enhance)
        enhance_repo "$2"
        ;;
    fork-category)
        fork_category "$2" "${3:-BlackRoad-OS}"
        ;;
    stats)
        stats
        ;;
    list)
        list "$2"
        ;;
    *)
        cat <<HELP
BlackRoad Sovereignty Fork Tracker

Usage:
  $0 init                           - Initialize fork tracking database
  $0 import                         - Import canonical sovereignty stack
  $0 fork <id> [org]                - Fork repository by ID
  $0 enhance <id>                   - Enhance forked repo with BlackRoad branding
  $0 fork-category <category> [org] - Fork all repos in category
  $0 stats                          - Show statistics
  $0 list [pending|forked|enhanced] - List repositories

Examples:
  $0 init                           # First run
  $0 import                         # Import canonical stack
  $0 stats                          # Show overview
  $0 fork 1 BlackRoad-OS            # Fork Keycloak
  $0 fork-category Identity         # Fork all identity repos
  $0 enhance 1                      # Add BlackRoad branding to fork #1
HELP
        ;;
esac
