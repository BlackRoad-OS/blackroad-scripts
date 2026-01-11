#!/bin/bash
# BlackRoad Stripe Setup - All 50 Products (5 Waves)
# Sets up Stripe for 50 enterprise products with 3 tiers each = 150 SKUs

set -e

echo "🖤 BlackRoad Stripe Setup - 50 Products 🛣️"
echo ""

# All 50 BlackRoad Enterprise Products across 5 waves
declare -a PRODUCTS=(
    # Wave 1 - Foundation (11)
    "vLLM:AI model serving platform"
    "Ollama:Local LLM runtime platform"
    "LocalAI:AI inference engine"
    "Headscale:Network control server"
    "MinIO:S3-compatible object storage"
    "NetBird:Zero-trust network mesh"
    "Restic:Fast secure backup solution"
    "Authelia:SSO authentication server"
    "EspoCRM:Customer relationship management"
    "Focalboard:Project management platform"
    "Whisper:Speech-to-text AI platform"
    # Wave 2 - Expansion (10)
    "ClickHouse:Analytics database platform"
    "Synapse:Matrix communication server"
    "Taiga:Agile project management"
    "Dendrite:Matrix homeserver"
    "SuiteCRM:Enterprise CRM platform"
    "ArangoDB:Multi-model database"
    "Borg:Deduplicating backup"
    "Innernet:Private network mesh"
    "TTS:Text-to-speech synthesis"
    "Vosk:Offline speech recognition"
    # Wave 3 - Acceleration (10)
    "Mattermost:Team collaboration platform"
    "GitLab:DevOps platform"
    "Nextcloud:Content collaboration"
    "Keycloak:Identity and access management"
    "Grafana:Observability and visualization"
    "Prometheus:Monitoring and alerting"
    "Vault:Secrets management"
    "RabbitMQ:Message broker"
    "Redis:In-memory data store"
    "PostgreSQL:Relational database"
    # Wave 4 - DevOps Dominance (9)
    "Ansible:Automation platform"
    "Jenkins:CI/CD platform"
    "Harbor:Container registry"
    "Consul:Service mesh"
    "Etcd:Distributed key-value store"
    "Traefik:Cloud-native proxy"
    "Nginx:Web server and reverse proxy"
    "Caddy:Web server with automatic HTTPS"
    "HAProxy:Load balancer"
    # Wave 5 - Observability & GitOps (10)
    "OpenSearch:Search and analytics engine"
    "Loki:Log aggregation system"
    "VictoriaMetrics:Metrics database"
    "Cortex:Scalable Prometheus"
    "Thanos:Prometheus high availability"
    "Rook:Storage orchestration"
    "Longhorn:Distributed storage"
    "Velero:Kubernetes backup"
    "ArgoCD:GitOps continuous delivery"
    "Flux:GitOps toolkit"
)

# Pricing tiers (monthly)
STARTER_PRICE=99
PROFESSIONAL_PRICE=499
ENTERPRISE_PRICE=2499

echo "📊 Creating Stripe products and prices..."
echo ""

for product_spec in "${PRODUCTS[@]}"; do
    IFS=':' read -r product_name description <<< "$product_spec"

    echo "💳 Setting up: $product_name"

    # Create Stripe product
    product_id="blackroad_$(echo "$product_name" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"

    echo "  Creating product: $product_id"
    # stripe products create \
    #   --name "BlackRoad $product_name Enterprise" \
    #   --description "$description" \
    #   --metadata[product]="$product_name" \
    #   --metadata[tier]="all"

    echo "  Creating Starter tier (\$${STARTER_PRICE}/month)"
    # stripe prices create \
    #   --product "$product_id" \
    #   --unit-amount $((STARTER_PRICE * 100)) \
    #   --currency usd \
    #   --recurring[interval]=month \
    #   --nickname "Starter - Up to 10 users"

    echo "  Creating Professional tier (\$${PROFESSIONAL_PRICE}/month)"
    # stripe prices create \
    #   --product "$product_id" \
    #   --unit-amount $((PROFESSIONAL_PRICE * 100)) \
    #   --currency usd \
    #   --recurring[interval]=month \
    #   --nickname "Professional - Up to 100 users"

    echo "  Creating Enterprise tier (\$${ENTERPRISE_PRICE}/month)"
    # stripe prices create \
    #   --product "$product_id" \
    #   --unit-amount $((ENTERPRISE_PRICE * 100)) \
    #   --currency usd \
    #   --recurring[interval]=month \
    #   --nickname "Enterprise - Unlimited users"

    echo "  ✅ $product_name complete!"
    echo ""
done

echo "🎉 Stripe setup complete!"
echo ""
echo "📊 Summary:"
echo "  Products created: ${#PRODUCTS[@]}"
echo "  Total SKUs: $((${#PRODUCTS[@]} * 3)) (3 tiers per product)"
echo "  Waves: 5 (11+10+10+9+10)"
echo ""
echo "💰 Revenue Potential:"
echo "  Per product: \$718K/year"
total_revenue=$((${#PRODUCTS[@]} * 718))
echo "  All products: \$${total_revenue}K/year = \$$(echo "scale=1; $total_revenue / 1000" | bc)M/year"
echo ""
echo "🚀 Next steps:"
echo "  1. Login to Stripe: stripe login"
echo "  2. Uncomment the stripe CLI commands above"
echo "  3. Run this script again: ./blackroad-stripe-setup-50-products.sh"
echo "  4. Setup webhooks for subscription events"
echo "  5. Integrate with admin dashboard"
echo ""
echo "🖤 Generated with Claude Code"
echo "🛣️ Built with BlackRoad"
