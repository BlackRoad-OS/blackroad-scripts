#!/bin/bash
# License Guardian - Automated License Compliance
# BlackRoad OS, Inc. © 2026

GUARDIAN_DIR="$HOME/.blackroad/license-guardian"
GUARDIAN_DB="$GUARDIAN_DIR/guardian.db"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Official BlackRoad License
BLACKROAD_LICENSE='MIT License

Copyright (c) 2026 BlackRoad OS, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.'

init() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     ⚖️  License Guardian                      ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    mkdir -p "$GUARDIAN_DIR/reports"

    # Create database
    sqlite3 "$GUARDIAN_DB" <<'SQL'
-- Repositories
CREATE TABLE IF NOT EXISTS repositories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    path TEXT NOT NULL,
    license_type TEXT,
    compliant INTEGER DEFAULT 0,
    last_checked INTEGER,
    issues TEXT                        -- JSON array of issues
);

-- License checks
CREATE TABLE IF NOT EXISTS license_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    check_type TEXT NOT NULL,          -- file_exists, content_valid, header_check
    status TEXT NOT NULL,              -- pass, fail, warn
    details TEXT,
    checked_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id)
);

-- Fixes applied
CREATE TABLE IF NOT EXISTS fixes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo_id INTEGER NOT NULL,
    fix_type TEXT NOT NULL,
    description TEXT,
    applied_at INTEGER NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(id)
);

CREATE INDEX IF NOT EXISTS idx_repositories_compliant ON repositories(compliant);
CREATE INDEX IF NOT EXISTS idx_license_checks_repo ON license_checks(repo_id);

SQL

    echo -e "${GREEN}✓${NC} License Guardian initialized"
}

# Scan repository
scan_repo() {
    local repo_path="$1"

    if [ ! -d "$repo_path" ]; then
        echo -e "${RED}Error: Repository not found: $repo_path${NC}"
        return 1
    fi

    local repo_name=$(basename "$repo_path")
    local timestamp=$(date +%s)

    echo -e "${CYAN}🔍 Scanning: $repo_name${NC}"

    # Check if LICENSE file exists
    local license_exists=0
    local license_file=""

    for file in LICENSE LICENSE.md LICENSE.txt; do
        if [ -f "$repo_path/$file" ]; then
            license_exists=1
            license_file="$file"
            break
        fi
    done

    local compliant=1
    local issues="[]"

    if [ $license_exists -eq 0 ]; then
        echo -e "  ${RED}✗${NC} No LICENSE file found"
        compliant=0
        issues='["missing_license_file"]'
    else
        echo -e "  ${GREEN}✓${NC} LICENSE file found: $license_file"

        # Check if it contains BlackRoad copyright
        if grep -q "BlackRoad OS, Inc." "$repo_path/$license_file"; then
            echo -e "  ${GREEN}✓${NC} Contains BlackRoad copyright"
        else
            echo -e "  ${YELLOW}!${NC} Missing BlackRoad copyright"
            compliant=0
            issues='["missing_copyright"]'
        fi

        # Check year
        local current_year=$(date +%Y)
        if grep -q "$current_year" "$repo_path/$license_file"; then
            echo -e "  ${GREEN}✓${NC} Copyright year is current"
        else
            echo -e "  ${YELLOW}!${NC} Copyright year may be outdated"
            issues='["outdated_year"]'
        fi
    fi

    # Store in database
    sqlite3 "$GUARDIAN_DB" <<SQL
INSERT OR REPLACE INTO repositories (name, path, license_type, compliant, last_checked, issues)
VALUES ('$repo_name', '$repo_path', 'MIT', $compliant, $timestamp, '$issues');
SQL

    local repo_id=$(sqlite3 "$GUARDIAN_DB" "SELECT id FROM repositories WHERE name = '$repo_name'")

    # Record check
    sqlite3 "$GUARDIAN_DB" <<SQL
INSERT INTO license_checks (repo_id, check_type, status, checked_at)
VALUES ($repo_id, 'file_exists', '$([ $license_exists -eq 1 ] && echo "pass" || echo "fail")', $timestamp);
SQL

    if [ $compliant -eq 1 ]; then
        echo -e "  ${GREEN}✅ COMPLIANT${NC}\n"
    else
        echo -e "  ${RED}❌ NON-COMPLIANT${NC}\n"
    fi
}

# Fix repository
fix_repo() {
    local repo_path="$1"

    if [ ! -d "$repo_path" ]; then
        echo -e "${RED}Error: Repository not found: $repo_path${NC}"
        return 1
    fi

    local repo_name=$(basename "$repo_path")
    echo -e "${CYAN}🔧 Fixing: $repo_name${NC}"

    # Write LICENSE file
    echo "$BLACKROAD_LICENSE" > "$repo_path/LICENSE"

    echo -e "  ${GREEN}✓${NC} LICENSE file created/updated"

    # Update database
    local timestamp=$(date +%s)
    local repo_id=$(sqlite3 "$GUARDIAN_DB" "SELECT id FROM repositories WHERE name = '$repo_name'")

    sqlite3 "$GUARDIAN_DB" <<SQL
UPDATE repositories
SET compliant = 1, last_checked = $timestamp, issues = '[]'
WHERE name = '$repo_name';

INSERT INTO fixes (repo_id, fix_type, description, applied_at)
VALUES ($repo_id, 'license_added', 'Added BlackRoad MIT license', $timestamp);
SQL

    echo -e "${GREEN}✅ Repository fixed!${NC}\n"

    # Log to memory
    ~/memory-system.sh log "license-fixed" "$repo_name" "License Guardian fixed licensing for $repo_name" "compliance,legal" 2>/dev/null
}

# Scan all repos in directory
scan_all() {
    local base_dir="${1:-.}"

    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     Scanning All Repositories                 ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    local count=0
    local compliant=0

    for repo in "$base_dir"/*; do
        if [ -d "$repo/.git" ]; then
            scan_repo "$repo"
            count=$((count + 1))

            # Check if compliant
            local is_compliant=$(sqlite3 "$GUARDIAN_DB" "SELECT compliant FROM repositories WHERE name = '$(basename $repo)'")
            if [ "$is_compliant" = "1" ]; then
                compliant=$((compliant + 1))
            fi
        fi
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Total repositories scanned:${NC} $count"
    echo -e "${GREEN}Compliant:${NC} $compliant"
    echo -e "${RED}Non-compliant:${NC} $((count - compliant))"
}

# Fix all non-compliant repos
fix_all() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     Fixing All Non-Compliant Repositories     ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    local repos=$(sqlite3 "$GUARDIAN_DB" "SELECT name, path FROM repositories WHERE compliant = 0")

    echo "$repos" | while IFS='|' read -r name path; do
        [ -z "$name" ] && continue
        fix_repo "$path"
    done

    echo -e "${GREEN}✅ All repositories fixed!${NC}"
}

# Report
report() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     ⚖️  License Compliance Report             ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    local total=$(sqlite3 "$GUARDIAN_DB" "SELECT COUNT(*) FROM repositories")
    local compliant=$(sqlite3 "$GUARDIAN_DB" "SELECT COUNT(*) FROM repositories WHERE compliant = 1")
    local non_compliant=$(sqlite3 "$GUARDIAN_DB" "SELECT COUNT(*) FROM repositories WHERE compliant = 0")
    local total_fixes=$(sqlite3 "$GUARDIAN_DB" "SELECT COUNT(*) FROM fixes")

    local compliance_rate=0
    if [ "$total" -gt 0 ]; then
        compliance_rate=$((compliant * 100 / total))
    fi

    echo -e "${CYAN}📊 Statistics${NC}"
    echo -e "  ${GREEN}Total Repositories:${NC} $total"
    echo -e "  ${GREEN}Compliant:${NC} $compliant"
    echo -e "  ${RED}Non-Compliant:${NC} $non_compliant"
    echo -e "  ${PURPLE}Compliance Rate:${NC} ${compliance_rate}%"
    echo -e "  ${PURPLE}Fixes Applied:${NC} $total_fixes"

    echo -e "\n${CYAN}❌ Non-Compliant Repositories${NC}"
    sqlite3 -header -column "$GUARDIAN_DB" <<SQL
SELECT name, issues
FROM repositories
WHERE compliant = 0
ORDER BY name;
SQL
}

# Main execution
case "${1:-help}" in
    init)
        init
        ;;
    scan)
        scan_repo "$2"
        ;;
    fix)
        fix_repo "$2"
        ;;
    scan-all)
        scan_all "$2"
        ;;
    fix-all)
        fix_all
        ;;
    report)
        report
        ;;
    help|*)
        echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║     ⚖️  License Guardian                      ║${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"
        echo "Automated license compliance for BlackRoad"
        echo ""
        echo "Usage: $0 COMMAND [OPTIONS]"
        echo ""
        echo "Setup:"
        echo "  init                    - Initialize License Guardian"
        echo ""
        echo "Operations:"
        echo "  scan REPO_PATH          - Scan single repository"
        echo "  fix REPO_PATH           - Fix single repository"
        echo "  scan-all [DIR]          - Scan all repos in directory"
        echo "  fix-all                 - Fix all non-compliant repos"
        echo "  report                  - Show compliance report"
        echo ""
        echo "Examples:"
        echo "  $0 scan ~/repos/blackroad-os-web"
        echo "  $0 fix ~/repos/blackroad-os-web"
        echo "  $0 scan-all ~/repos"
        echo "  $0 fix-all"
        ;;
esac
