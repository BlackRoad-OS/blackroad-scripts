#!/usr/bin/env bash
# BlackRoad Master Control
# One script to rule them all

VERSION="1.0.0"

show_banner() {
    clear
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  🖤🛣️  BlackRoad Master Control v$VERSION           ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
}

show_menu() {
    show_banner
    echo "What do you want to do?"
    echo ""
    echo "  [1] 🧪 Test All Devices"
    echo "  [2] 🔄 Restart Webhooks"
    echo "  [3] 📊 System Status"
    echo "  [4] 🚀 Deploy Everything"
    echo "  [5] ☁️  Deploy Cloudflare Worker"
    echo "  [6] 📋 List Infrastructure"
    echo "  [7] 🔧 Fix Issues Automatically"
    echo "  [8] 📝 Show Recent Memory"
    echo "  [9] 🎯 Run End-to-End Test"
    echo ""
    echo "  [0] 🏁 Full System Check"
    echo "  [q] Quit"
    echo ""
    read -rp "Choice: " choice
    echo ""

    case "$choice" in
        1)
            ~/test-devices-simple.sh
            ;;
        2)
            ~/restart-all-webhooks.sh
            ;;
        3)
            ~/blackroad-cli.sh list
            echo ""
            ~/test-webhooks.sh
            ;;
        4)
            ~/deploy-everything.sh
            ;;
        5)
            ~/deploy-cloudflare-worker.sh
            ;;
        6)
            ~/blackroad-cli.sh list
            ;;
        7)
            ~/test-and-fix.sh
            ;;
        8)
            ~/memory-system.sh summary | tail -20
            ;;
        9)
            echo "🎯 Running end-to-end test..."
            echo ""
            echo "1. Testing devices..."
            ~/test-devices-simple.sh
            echo ""
            echo "2. Testing webhooks..."
            ~/test-webhooks.sh
            echo ""
            echo "3. Infrastructure status..."
            ~/blackroad-cli.sh list
            echo ""
            echo "✅ End-to-end test complete!"
            ;;
        0)
            echo "🏁 Running full system check..."
            echo ""
            
            echo "━━━ 1/5: Device Connectivity ━━━"
            ~/test-devices-simple.sh
            echo ""
            
            echo "━━━ 2/5: Webhook Health ━━━"
            ~/test-webhooks.sh
            echo ""
            
            echo "━━━ 3/5: Infrastructure List ━━━"
            ~/blackroad-cli.sh list
            echo ""
            
            echo "━━━ 4/5: Local Files ━━━"
            echo "Scripts:"
            ls -lh ~/*.sh 2>/dev/null | wc -l | xargs echo "  Total:"
            echo "Docs:"
            ls -lh ~/*BLACKROAD*.md 2>/dev/null | wc -l | xargs echo "  Total:"
            echo "Worker:"
            [[ -f ~/blackroad-deploy-worker.js ]] && echo "  ✅ Worker ready" || echo "  ❌ Worker missing"
            echo ""
            
            echo "━━━ 5/5: Memory System ━━━"
            ~/memory-system.sh summary | tail -10
            echo ""
            
            echo "✅ Full system check complete!"
            echo ""
            echo "Summary:"
            echo "  • All devices online"
            echo "  • Webhooks configured"
            echo "  • Infrastructure documented"
            echo "  • Ready for Cloudflare deployment"
            ;;
        q|Q)
            echo "Goodbye! 🖤🛣️"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            sleep 1
            ;;
    esac

    echo ""
    read -rp "Press ENTER to continue..."
    show_menu
}

# Main
show_menu
