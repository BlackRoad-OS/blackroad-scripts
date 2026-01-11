#!/bin/bash
# BlackRoad Cloudflare Worker Mass Deployer
# Deploys 80 workers across 16 zones for 30K agent infrastructure
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
WORKER_DIR="$HOME/.blackroad/workers"
DEPLOYMENT_DB="$HOME/.blackroad/workers/deployments.db"

ZONES=(
    "blackroad.io"
    "lucidia.earth"
    "blackroadai.com"
    "blackroadquantum.com"
    "blackroadinc.us"
    "blackroad.me"
    "blackroad.systems"
    "blackroad-os.com"
    "blackroad.dev"
    "lucidia.io"
    "lucidia.com"
    "blackbox.enterprises"
    "blackboxprogramming.com"
    "quantumphysics.energy"
    "nativeai.earth"
    "universalcomputer.io"
)

# Initialize
init_db() {
    mkdir -p "$WORKER_DIR"

    sqlite3 "$DEPLOYMENT_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS workers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    worker_name TEXT NOT NULL UNIQUE,
    zone_name TEXT NOT NULL,
    worker_type TEXT NOT NULL,
    worker_number INTEGER NOT NULL,
    deployment_status TEXT DEFAULT 'pending',
    worker_url TEXT,
    deployed_at TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS deployment_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total_workers INTEGER DEFAULT 80,
    deployed_workers INTEGER DEFAULT 0,
    failed_workers INTEGER DEFAULT 0,
    pending_workers INTEGER DEFAULT 80,
    last_deployment TEXT,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO deployment_stats (total_workers, deployed_workers, failed_workers, pending_workers)
VALUES (80, 0, 0, 80);

CREATE INDEX IF NOT EXISTS idx_workers_status ON workers(deployment_status);
CREATE INDEX IF NOT EXISTS idx_workers_zone ON workers(zone_name);
SQL

    echo -e "${GREEN}[WORKER-DEPLOYER]${NC} Database initialized!"
}

# Generate advanced load balancer worker
generate_advanced_worker() {
    local zone_name="$1"
    local worker_num="$2"
    local worker_name="${zone_name//./-}-lb-${worker_num}"

    cat > "$WORKER_DIR/${worker_name}.js" <<'WORKER'
// BlackRoad 30K Agent Load Balancer - Advanced Edition
// Zone: __ZONE_NAME__
// Worker: #__WORKER_NUM__
// CEO: Alexa Amundson

const RATE_LIMIT_WINDOW = 60; // 60 seconds
const MAX_REQUESTS_PER_MINUTE = 10;
const MAX_CPU_TIME = 50; // milliseconds

export default {
  async fetch(request, env, ctx) {
    const startTime = Date.now();

    try {
      // CORS headers for cross-origin requests
      const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Agent-ID, X-User-Type',
      };

      // Handle OPTIONS request
      if (request.method === 'OPTIONS') {
        return new Response(null, { headers: corsHeaders });
      }

      const url = new URL(request.url);

      // Extract user info
      const userType = request.headers.get('X-User-Type') || 'unknown';
      const userId = request.headers.get('X-Agent-ID') ||
                     request.headers.get('X-Employee-ID') ||
                     request.headers.get('X-Forwarded-For') ||
                     'anonymous';

      // Rate limiting
      const rateLimitKey = `rate:${userId}:${Math.floor(Date.now() / (RATE_LIMIT_WINDOW * 1000))}`;

      let requestCount = 0;
      try {
        const cached = await env.RATE_LIMIT_KV.get(rateLimitKey);
        requestCount = cached ? parseInt(cached) : 0;
      } catch (e) {
        console.error('Rate limit check failed:', e);
      }

      if (requestCount >= MAX_REQUESTS_PER_MINUTE) {
        return new Response(JSON.stringify({
          error: 'Rate limit exceeded',
          limit: MAX_REQUESTS_PER_MINUTE,
          window: RATE_LIMIT_WINDOW,
          retry_after: RATE_LIMIT_WINDOW
        }), {
          status: 429,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json',
            'Retry-After': RATE_LIMIT_WINDOW.toString()
          }
        });
      }

      // Increment rate limit
      try {
        await env.RATE_LIMIT_KV.put(
          rateLimitKey,
          (requestCount + 1).toString(),
          { expirationTtl: RATE_LIMIT_WINDOW * 2 }
        );
      } catch (e) {
        console.error('Rate limit increment failed:', e);
      }

      // Route handling
      switch (url.pathname) {
        case '/':
          return handleRoot(corsHeaders);

        case '/health':
          return handleHealth(env, startTime, corsHeaders);

        case '/metrics':
          return handleMetrics(env, startTime, corsHeaders);

        case '/agent/register':
          return handleAgentRegister(request, env, userId, userType, startTime, corsHeaders);

        case '/agent/heartbeat':
          return handleAgentHeartbeat(request, env, userId, startTime, corsHeaders);

        case '/agent/task':
          return handleAgentTask(request, env, userId, startTime, corsHeaders);

        case '/ceo/dashboard':
          return handleCEODashboard(env, startTime, corsHeaders);

        default:
          return new Response(JSON.stringify({
            error: 'Not Found',
            path: url.pathname
          }), {
            status: 404,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          });
      }

    } catch (error) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({
        error: 'Internal Server Error',
        message: error.message
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
};

// Handler: Root
function handleRoot(corsHeaders) {
  return new Response(JSON.stringify({
    service: 'BlackRoad 30K Agent Infrastructure',
    zone: '__ZONE_NAME__',
    worker: '__WORKER_NUM__',
    capacity: {
      agents: 30000,
      employees: 30000,
      total: 60000
    },
    ceo: 'Alexa Amundson',
    organization: 'BlackRoad OS, Inc.',
    endpoints: [
      '/health',
      '/metrics',
      '/agent/register',
      '/agent/heartbeat',
      '/agent/task',
      '/ceo/dashboard'
    ]
  }), {
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'X-CEO': 'Alexa Amundson',
      'X-Zone': '__ZONE_NAME__'
    }
  });
}

// Handler: Health check
async function handleHealth(env, startTime, corsHeaders) {
  const processingTime = Date.now() - startTime;

  let kvHealthy = false;
  let d1Healthy = false;

  try {
    await env.RATE_LIMIT_KV.get('health-check');
    kvHealthy = true;
  } catch (e) {
    console.error('KV health check failed:', e);
  }

  try {
    const result = await env.ANALYTICS_DB.prepare('SELECT 1').first();
    d1Healthy = true;
  } catch (e) {
    console.error('D1 health check failed:', e);
  }

  const healthy = kvHealthy && d1Healthy && processingTime < MAX_CPU_TIME;

  return new Response(JSON.stringify({
    status: healthy ? 'healthy' : 'degraded',
    timestamp: Date.now(),
    processing_time_ms: processingTime,
    components: {
      kv: kvHealthy ? 'healthy' : 'unhealthy',
      d1: d1Healthy ? 'healthy' : 'unhealthy',
      cpu: processingTime < MAX_CPU_TIME ? 'healthy' : 'slow'
    },
    zone: '__ZONE_NAME__',
    worker: '__WORKER_NUM__',
    ceo: 'Alexa Amundson'
  }), {
    status: healthy ? 200 : 503,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

// Handler: Metrics
async function handleMetrics(env, startTime, corsHeaders) {
  try {
    const result = await env.ANALYTICS_DB.prepare(`
      SELECT
        COUNT(*) as total_requests,
        COUNT(DISTINCT agent_id) as unique_agents
      FROM requests
      WHERE timestamp > ?
    `).bind(Date.now() - 60000).first();

    return new Response(JSON.stringify({
      zone: '__ZONE_NAME__',
      worker: '__WORKER_NUM__',
      last_minute: {
        total_requests: result?.total_requests || 0,
        unique_agents: result?.unique_agents || 0
      },
      processing_time_ms: Date.now() - startTime,
      timestamp: Date.now()
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: 'Metrics unavailable',
      message: e.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Handler: Agent registration
async function handleAgentRegister(request, env, userId, userType, startTime, corsHeaders) {
  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  try {
    const body = await request.json();
    const agentId = body.agent_id || userId;
    const agentType = body.agent_type || 'general';

    // Store in D1
    await env.ANALYTICS_DB.prepare(`
      INSERT OR REPLACE INTO agents (agent_id, agent_type, zone, registered_at)
      VALUES (?, ?, ?, ?)
    `).bind(agentId, agentType, '__ZONE_NAME__', Date.now()).run();

    // Cache in KV
    await env.SESSION_KV.put(`agent:${agentId}`, JSON.stringify({
      agent_id: agentId,
      agent_type: agentType,
      zone: '__ZONE_NAME__',
      registered_at: Date.now()
    }), { expirationTtl: 3600 });

    return new Response(JSON.stringify({
      success: true,
      agent_id: agentId,
      agent_type: agentType,
      zone: '__ZONE_NAME__',
      worker: '__WORKER_NUM__',
      message: 'Agent registered successfully'
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: 'Registration failed',
      message: e.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Handler: Agent heartbeat
async function handleAgentHeartbeat(request, env, userId, startTime, corsHeaders) {
  if (request.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  try {
    const body = await request.json();
    const agentId = body.agent_id || userId;

    // Update heartbeat in D1
    await env.ANALYTICS_DB.prepare(`
      UPDATE agents SET last_heartbeat = ? WHERE agent_id = ?
    `).bind(Date.now(), agentId).run();

    return new Response(JSON.stringify({
      success: true,
      agent_id: agentId,
      timestamp: Date.now()
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: 'Heartbeat failed',
      message: e.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Handler: Agent task
async function handleAgentTask(request, env, userId, startTime, corsHeaders) {
  try {
    // Get pending task from queue
    const task = await env.TASK_QUEUE_KV.get('next-task');

    if (!task) {
      return new Response(JSON.stringify({
        message: 'No tasks available',
        agent_id: userId
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    return new Response(task, {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: 'Task retrieval failed',
      message: e.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Handler: CEO Dashboard
async function handleCEODashboard(env, startTime, corsHeaders) {
  try {
    const stats = await env.ANALYTICS_DB.prepare(`
      SELECT
        COUNT(*) as total_agents,
        COUNT(CASE WHEN last_heartbeat > ? THEN 1 END) as active_agents
      FROM agents
    `).bind(Date.now() - 300000).first(); // 5 min window

    return new Response(JSON.stringify({
      ceo: 'Alexa Amundson',
      organization: 'BlackRoad OS, Inc.',
      zone: '__ZONE_NAME__',
      worker: '__WORKER_NUM__',
      agents: {
        total: stats?.total_agents || 0,
        active: stats?.active_agents || 0,
        capacity: 30000
      },
      timestamp: Date.now(),
      processing_time_ms: Date.now() - startTime
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: 'Dashboard unavailable',
      message: e.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}
WORKER

    # Replace placeholders
    sed -i '' "s/__ZONE_NAME__/$zone_name/g" "$WORKER_DIR/${worker_name}.js"
    sed -i '' "s/__WORKER_NUM__/$worker_num/g" "$WORKER_DIR/${worker_name}.js"

    echo -e "${GREEN}✓${NC} Generated worker: ${worker_name}.js"
}

# Generate all workers
generate_all_workers() {
    echo -e "${BOLD}${CYAN}═══ GENERATING 80 CLOUDFLARE WORKERS ═══${NC}"
    echo ""

    local total=0
    for zone in "${ZONES[@]}"; do
        echo -e "${PURPLE}Zone: $zone${NC}"
        for i in {1..5}; do
            generate_advanced_worker "$zone" "$i"

            # Register in database
            local worker_name="${zone//./-}-lb-${i}"
            sqlite3 "$DEPLOYMENT_DB" <<SQL
INSERT OR IGNORE INTO workers (worker_name, zone_name, worker_type, worker_number, deployment_status)
VALUES ('$worker_name', '$zone', 'load-balancer', $i, 'generated');
SQL
            ((total++))
        done
        echo ""
    done

    echo -e "${GREEN}Generated $total workers!${NC}"
}

# Generate wrangler.toml
generate_wrangler_config() {
    local worker_name="$1"
    local zone_name="$2"

    cat > "$WORKER_DIR/${worker_name}-wrangler.toml" <<TOML
name = "${worker_name}"
main = "${worker_name}.js"
compatibility_date = "2024-01-01"

# KV Namespaces
[[kv_namespaces]]
binding = "RATE_LIMIT_KV"
id = "REPLACE_WITH_KV_ID"

[[kv_namespaces]]
binding = "SESSION_KV"
id = "REPLACE_WITH_KV_ID"

[[kv_namespaces]]
binding = "TASK_QUEUE_KV"
id = "REPLACE_WITH_KV_ID"

# D1 Database
[[d1_databases]]
binding = "ANALYTICS_DB"
database_name = "${zone_name//./-}-analytics"
database_id = "REPLACE_WITH_D1_ID"

# Routes
routes = [
  { pattern = "${zone_name}/*", zone_name = "${zone_name}" }
]

# Limits
[limits]
cpu_ms = 50
TOML

    echo -e "${GREEN}✓${NC} Generated config: ${worker_name}-wrangler.toml"
}

# Show deployment plan
show_deployment_plan() {
    echo -e "${BOLD}${PURPLE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${PURPLE}║                                                        ║${NC}"
    echo -e "${BOLD}${PURPLE}║   🚀 80 WORKER DEPLOYMENT PLAN 🚀                     ║${NC}"
    echo -e "${BOLD}${PURPLE}║                                                        ║${NC}"
    echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}═══ INFRASTRUCTURE ═══${NC}"
    echo -e "  Total Workers:     ${BOLD}80${NC}"
    echo -e "  Zones:             ${BOLD}16${NC}"
    echo -e "  Workers per Zone:  ${BOLD}5${NC}"
    echo -e "  KV Namespaces:     ${BOLD}48${NC} (3 per zone)"
    echo -e "  D1 Databases:      ${BOLD}32${NC} (2 per zone)"
    echo ""

    echo -e "${CYAN}═══ DEPLOYMENT PHASES ═══${NC}"
    echo -e "  Phase 1: Generate all worker files (80 files)"
    echo -e "  Phase 2: Create KV namespaces (48 namespaces)"
    echo -e "  Phase 3: Create D1 databases (32 databases)"
    echo -e "  Phase 4: Deploy workers (80 deployments)"
    echo -e "  Phase 5: Verify health checks (80 endpoints)"
    echo ""

    echo -e "${CYAN}═══ CURRENT STATUS ═══${NC}"
    sqlite3 -column "$DEPLOYMENT_DB" "
        SELECT
            deployment_status as status,
            COUNT(*) as count
        FROM workers
        GROUP BY deployment_status;
    " 2>/dev/null || echo "  Run 'init' first"
    echo ""
}

# Show stats
show_stats() {
    echo -e "${CYAN}━━━ Worker Deployment Statistics ━━━${NC}"
    echo ""

    sqlite3 -column "$DEPLOYMENT_DB" "
        SELECT
            zone_name,
            COUNT(*) as workers,
            SUM(CASE WHEN deployment_status='deployed' THEN 1 ELSE 0 END) as deployed,
            SUM(CASE WHEN deployment_status='generated' THEN 1 ELSE 0 END) as generated
        FROM workers
        GROUP BY zone_name;
    " 2>/dev/null

    echo ""
    echo -e "${CYAN}━━━ Overall Stats ━━━${NC}"
    sqlite3 -column "$DEPLOYMENT_DB" "SELECT * FROM deployment_stats;" 2>/dev/null
}

# Help
show_help() {
    cat <<EOF
${CYAN}BlackRoad Cloudflare Worker Mass Deployer${NC}

Deploys 80 workers across 16 zones for 30K agent infrastructure

USAGE:
    blackroad-worker-deployer.sh <command>

COMMANDS:
    init                Initialize deployment system
    generate            Generate all 80 worker files
    plan                Show deployment plan
    stats               Show deployment statistics
    help                Show this help

EXAMPLES:
    # Initialize
    blackroad-worker-deployer.sh init

    # Generate all workers
    blackroad-worker-deployer.sh generate

    # Show plan
    blackroad-worker-deployer.sh plan

WORKERS: 80 total (5 per zone × 16 zones)
CEO: Alexa Amundson
EOF
}

# Main
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        init)
            init_db
            ;;
        generate)
            generate_all_workers
            ;;
        plan)
            show_deployment_plan
            ;;
        stats)
            show_stats
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
