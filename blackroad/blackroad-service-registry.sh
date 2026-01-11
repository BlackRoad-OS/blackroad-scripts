#!/bin/bash
# BlackRoad Service Registry
# Central registry for all services across all 15 divisions

set -euo pipefail

DB_FILE="$HOME/.blackroad/service-registry.db"
mkdir -p "$(dirname "$DB_FILE")"

# Initialize database if it doesn't exist
init_db() {
    if [ ! -f "$DB_FILE" ]; then
        sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE IF NOT EXISTS services (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    organization TEXT NOT NULL,
    repository TEXT NOT NULL,
    upstream TEXT,
    category TEXT,
    priority TEXT,
    status TEXT DEFAULT 'forked',
    endpoint TEXT,
    health_check TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization, repository)
);

CREATE TABLE IF NOT EXISTS dependencies (
    service_id INTEGER,
    depends_on_service_id INTEGER,
    dependency_type TEXT,
    FOREIGN KEY (service_id) REFERENCES services(id),
    FOREIGN KEY (depends_on_service_id) REFERENCES services(id),
    PRIMARY KEY (service_id, depends_on_service_id)
);

CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    service_id INTEGER,
    metric_name TEXT,
    metric_value REAL,
    recorded_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (service_id) REFERENCES services(id)
);

CREATE INDEX idx_org ON services(organization);
CREATE INDEX idx_status ON services(status);
CREATE INDEX idx_category ON services(category);
SQL
        echo "✅ Service registry database initialized"
    fi
}

# Register a new service
register() {
    local org=$1
    local repo=$2
    local upstream=${3:-}
    local category=${4:-}
    local priority=${5:-}

    init_db

    sqlite3 "$DB_FILE" <<SQL
INSERT OR REPLACE INTO services (organization, repository, upstream, category, priority, updated_at)
VALUES ('$org', '$repo', '$upstream', '$category', '$priority', datetime('now'));
SQL

    echo "✅ Registered: $org/$repo"
}

# Update service status
update_status() {
    local org=$1
    local repo=$2
    local status=$3
    local endpoint=${4:-}
    local health_check=${5:-}

    init_db

    sqlite3 "$DB_FILE" <<SQL
UPDATE services
SET status = '$status',
    endpoint = '$endpoint',
    health_check = '$health_check',
    updated_at = datetime('now')
WHERE organization = '$org' AND repository = '$repo';
SQL

    echo "✅ Updated status: $org/$repo → $status"
}

# List all services
list() {
    local filter=${1:-}

    init_db

    if [ -z "$filter" ]; then
        sqlite3 -header -column "$DB_FILE" "SELECT organization, repository, status, category, priority FROM services ORDER BY organization, repository;"
    else
        sqlite3 -header -column "$DB_FILE" "SELECT organization, repository, status, category, priority FROM services WHERE organization = '$filter' ORDER BY repository;"
    fi
}

# Show service details
show() {
    local org=$1
    local repo=$2

    init_db

    sqlite3 -header -column "$DB_FILE" "SELECT * FROM services WHERE organization = '$org' AND repository = '$repo';"
}

# Statistics
stats() {
    init_db

    echo "🖤🛣️  BlackRoad Service Registry Statistics"
    echo "==========================================="
    echo ""

    echo "By Organization:"
    sqlite3 -header -column "$DB_FILE" "SELECT organization, COUNT(*) as count FROM services GROUP BY organization ORDER BY count DESC;"

    echo ""
    echo "By Status:"
    sqlite3 -header -column "$DB_FILE" "SELECT status, COUNT(*) as count FROM services GROUP BY status ORDER BY count DESC;"

    echo ""
    echo "By Category:"
    sqlite3 -header -column "$DB_FILE" "SELECT category, COUNT(*) as count FROM services WHERE category IS NOT NULL GROUP BY category ORDER BY count DESC;"

    echo ""
    echo "Total Services: $(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM services;")"
}

# Export to JSON
export_json() {
    init_db

    sqlite3 "$DB_FILE" <<'SQL' | jq .
.mode json
SELECT
    organization,
    repository,
    upstream,
    category,
    priority,
    status,
    endpoint,
    health_check,
    created_at,
    updated_at
FROM services
ORDER BY organization, repository;
SQL
}

# Generate service map
service_map() {
    init_db

    cat > /tmp/blackroad-service-map.md <<'EOF'
# BlackRoad Service Map
## All Services Across All Divisions

Generated: $(date)

EOF

    for org in $(sqlite3 "$DB_FILE" "SELECT DISTINCT organization FROM services ORDER BY organization;"); do
        echo "" >> /tmp/blackroad-service-map.md
        echo "### $org" >> /tmp/blackroad-service-map.md
        echo "" >> /tmp/blackroad-service-map.md

        sqlite3 -header -markdown "$DB_FILE" "SELECT repository, status, category, endpoint FROM services WHERE organization = '$org' ORDER BY repository;" >> /tmp/blackroad-service-map.md
    done

    echo "✅ Service map generated: /tmp/blackroad-service-map.md"
    cat /tmp/blackroad-service-map.md
}

# Health check all services
health_check_all() {
    init_db

    echo "🏥 Checking health of all services..."
    echo ""

    sqlite3 "$DB_FILE" "SELECT id, organization, repository, endpoint, health_check FROM services WHERE endpoint IS NOT NULL;" | while IFS='|' read -r id org repo endpoint health_check; do
        echo -n "Checking $org/$repo... "

        if [ -n "$health_check" ]; then
            if curl -sf "$health_check" > /dev/null; then
                echo "✅ healthy"
                sqlite3 "$DB_FILE" "INSERT INTO metrics (service_id, metric_name, metric_value) VALUES ($id, 'health', 1);"
            else
                echo "❌ unhealthy"
                sqlite3 "$DB_FILE" "INSERT INTO metrics (service_id, metric_name, metric_value) VALUES ($id, 'health', 0);"
            fi
        else
            echo "⏭️  no health check"
        fi
    done
}

# Usage
case "${1:-help}" in
    init)
        init_db
        ;;
    register)
        register "${2}" "${3}" "${4:-}" "${5:-}" "${6:-}"
        ;;
    update)
        update_status "${2}" "${3}" "${4}" "${5:-}" "${6:-}"
        ;;
    list)
        list "${2:-}"
        ;;
    show)
        show "${2}" "${3}"
        ;;
    stats)
        stats
        ;;
    export)
        export_json
        ;;
    map)
        service_map
        ;;
    health)
        health_check_all
        ;;
    *)
        echo "BlackRoad Service Registry"
        echo ""
        echo "Usage:"
        echo "  $0 init                                       - Initialize database"
        echo "  $0 register <org> <repo> [upstream] [cat] [pri] - Register service"
        echo "  $0 update <org> <repo> <status> [endpoint] [health] - Update service"
        echo "  $0 list [org]                                 - List services"
        echo "  $0 show <org> <repo>                          - Show service details"
        echo "  $0 stats                                      - Show statistics"
        echo "  $0 export                                     - Export to JSON"
        echo "  $0 map                                        - Generate service map"
        echo "  $0 health                                     - Check health of all services"
        echo ""
        echo "Example:"
        echo "  $0 register BlackRoad-AI blackroad-vllm https://github.com/vllm-project/vllm ai high"
        echo "  $0 update BlackRoad-AI blackroad-vllm deployed https://ai.blackroad.io https://ai.blackroad.io/health"
        ;;
esac
