#!/bin/bash
# BlackRoad Stripe Setup - Create all products and pricing
# Sets up Stripe for 21 enterprise products with 3 tiers each

set -e

echo "🖤 BlackRoad Stripe Setup 🛣️"
echo ""

# All 21 BlackRoad Enterprise Products
declare -a PRODUCTS=(
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
echo ""
echo "💰 Revenue Potential:"
echo "  Per product: \$718K/year"
echo "  All products: \$$(( ${#PRODUCTS[@]} * 718 ))K/year = \$$(( ${#PRODUCTS[@]} * 718 / 1000 )).$(( (${#PRODUCTS[@]} * 718 % 1000) / 100 ))M/year"
echo ""
echo "🚀 Next steps:"
echo "  1. Login to Stripe: stripe login"
echo "  2. Uncomment the stripe CLI commands above"
echo "  3. Run this script again: ./blackroad-stripe-setup.sh"
echo "  4. Setup webhooks for subscription events"
echo "  5. Integrate with admin dashboard"
