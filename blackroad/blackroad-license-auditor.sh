#!/bin/bash

# ═══════════════════════════════════════════════════════════
# ⚖️ BLACKROAD LICENSE AUDITOR & FIXER
# ═══════════════════════════════════════════════════════════
# Audit and fix LICENSE files across ALL BlackRoad-OS repos
# Ensures proper BlackRoad OS, Inc. proprietary licensing
# Agent: cecilia-production-enhancer-3ce313b2
# ═══════════════════════════════════════════════════════════

set -e

REPO_NAME="$1"
ORG="${2:-BlackRoad-OS}"
WORK_DIR="/tmp/license-audit-$$"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}⚖️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

if [ -z "$REPO_NAME" ]; then
    echo "Usage: $0 <repo-name> [org]"
    exit 1
fi

log_info "Auditing LICENSE: $ORG/$REPO_NAME"

# Setup
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone
if ! gh repo clone "$ORG/$REPO_NAME"; then
    log_error "Failed to clone $REPO_NAME"
    exit 1
fi
cd "$REPO_NAME"

# Log to memory
~/memory-system.sh log started "license-auditing-$REPO_NAME" "Auditing and fixing LICENSE file" "cecilia,license,audit" 2>/dev/null || true

# Check current LICENSE
NEEDS_UPDATE=false

if [ ! -f "LICENSE" ]; then
    log_warning "No LICENSE file found - will create"
    NEEDS_UPDATE=true
elif ! grep -q "BlackRoad OS, Inc." LICENSE 2>/dev/null; then
    log_warning "LICENSE missing BlackRoad OS, Inc. - will update"
    NEEDS_UPDATE=true
elif ! grep -q "Alexa Amundson" LICENSE 2>/dev/null; then
    log_warning "LICENSE missing CEO info - will update"
    NEEDS_UPDATE=true
elif ! grep -q "NON-COMMERCIAL" LICENSE 2>/dev/null; then
    log_warning "LICENSE missing non-commercial clause - will update"
    NEEDS_UPDATE=true
fi

if [ "$NEEDS_UPDATE" = true ]; then
    # Create proper LICENSE file
    cat > LICENSE <<'EOF'
BlackRoad OS, Inc. - Proprietary License

Copyright (c) 2024-2026 BlackRoad OS, Inc.
All rights reserved.

CEO & Operator: Alexa Amundson
Email: blackroad.systems@gmail.com
Website: https://blackroad.io

IMPORTANT NOTICE:
This software and associated documentation files (the "Software") are the
exclusive property of BlackRoad OS, Inc.

LICENSE TERMS:

1. PROPRIETARY SOFTWARE
   This Software is proprietary and confidential to BlackRoad OS, Inc.

2. NON-COMMERCIAL USE
   This Software is provided for TESTING and DEVELOPMENT purposes only.
   Commercial use, resale, or redistribution is STRICTLY PROHIBITED.

3. PUBLIC VISIBILITY
   While this repository may be publicly visible on platforms like GitHub,
   this does NOT grant any rights to use, copy, modify, merge, publish,
   distribute, sublicense, or sell the Software.

4. NO COMMERCIAL RESALE
   This Software is NOT for commercial resale under any circumstances.

5. TESTING PURPOSES
   This Software is provided purely for testing, evaluation, and development
   purposes by BlackRoad OS, Inc. and authorized partners.

6. PROTECTION
   All intellectual property rights remain with BlackRoad OS, Inc.

7. NO WARRANTY
   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

8. LIMITATION OF LIABILITY
   IN NO EVENT SHALL BLACKROAD OS, INC. BE LIABLE FOR ANY CLAIM OR DAMAGES.

9. AUTHORIZED USE
   Use authorized for:
   - Internal testing by BlackRoad OS, Inc.
   - Supporting 30,000 AI agents
   - Supporting 30,000 human employees
   - CEO/Operator oversight (Alexa Amundson)

10. ENFORCEMENT
    BlackRoad OS, Inc. reserves all rights to enforce this license.

For permissions: blackroad.systems@gmail.com
EOF

    # Commit changes
    git add LICENSE

    if git diff --cached --quiet; then
        log_info "No changes needed"
    else
        git commit -m "⚖️ Update to BlackRoad OS, Inc. proprietary license

Enterprise proprietary license update:
- BlackRoad OS, Inc. copyright
- CEO: Alexa Amundson
- Non-commercial use only
- Testing purposes
- Public but legally protected
- Supports 30k agents + 30k employees

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"

        git push
        log_success "LICENSE updated: $REPO_NAME"

        ~/memory-system.sh log completed "license-fixed-$REPO_NAME" "LICENSE updated to BlackRoad OS, Inc. proprietary" "cecilia,license,fixed" 2>/dev/null || true
    fi
else
    log_success "LICENSE already correct: $REPO_NAME"
    ~/memory-system.sh log completed "license-verified-$REPO_NAME" "LICENSE verified correct" "cecilia,license,verified" 2>/dev/null || true
fi

cd "$WORK_DIR"
rm -rf "$REPO_NAME"

log_success "Audit complete!"
