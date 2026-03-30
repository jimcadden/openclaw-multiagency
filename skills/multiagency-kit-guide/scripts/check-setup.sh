#!/bin/bash
#
# check-setup.sh: Verify workspace health
#
# Usage: ./check-setup.sh
#

set -e

WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspaces}"
KIT_DIR="$WORKSPACE_DIR/kit"

errors=0
warnings=0

check_pass() { echo "  ✅ $1"; }
check_fail() { echo "  ❌ $1"; ((errors++)); }
check_warn() { echo "  ⚠️  $1"; ((warnings++)); }

echo "╔════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Workspace Health Check                       ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

# Check kit directory
echo "Checking kit..."
if [ -d "$KIT_DIR" ]; then
    check_pass "Kit directory exists"
    
    if [ -d "$KIT_DIR/.git" ] || [ -f "$KIT_DIR/.git" ]; then
        check_pass "Kit is a git repo"
        
        cd "$KIT_DIR"
        current=$(git describe --tags 2>/dev/null || echo "unknown")
        echo "     Version: $current"
        
        if git describe --tags --exact-match >/dev/null 2>&1; then
            check_pass "Kit is on a tagged release"
        else
            check_warn "Kit is not on a tag (may be on branch or detached HEAD)"
        fi
    else
        check_fail "Kit is not a git repo"
    fi
else
    check_fail "Kit directory missing"
fi

# Check shared skills
echo
echo "Checking shared skills..."
for skill in multiagency-state-manager multiagency-telegram-setup multiagency-add-agent multiagency-remove-agent multiagency-memory-manager; do
    if [ -L "$WORKSPACE_DIR/shared/skills/$skill" ]; then
        check_pass "$skill symlink exists"
    else
        check_fail "$skill symlink missing"
    fi
done

# Check skills.load.extraDirs in openclaw.json
echo
echo "Checking skills config..."
OC_CONFIG="${OPENCLAW_DIR:-$HOME/.openclaw}/openclaw.json"
if [ -f "$OC_CONFIG" ]; then
    SHARED_SKILLS="$WORKSPACE_DIR/shared/skills"
    if python3 -c "
import json, sys
with open('$OC_CONFIG') as f:
    c = json.load(f)
dirs = c.get('skills', {}).get('load', {}).get('extraDirs', [])
sys.exit(0 if '$SHARED_SKILLS' in dirs else 1)
" 2>/dev/null; then
        check_pass "skills.load.extraDirs contains shared/skills"
    else
        check_fail "skills.load.extraDirs missing '$SHARED_SKILLS'"
        check_fail "  Run install or migrate to fix, or add manually to $OC_CONFIG"
    fi
else
    check_warn "openclaw.json not found at $OC_CONFIG — cannot verify skills config"
fi

# Check agents
echo
echo "Checking agents..."
agent_count=0
for dir in "$WORKSPACE_DIR"/*/; do
    if [ -f "$dir/IDENTITY.md" ] && [ -f "$dir/SOUL.md" ]; then
        agent_name=$(basename "$dir")
        agent_count=$((agent_count + 1))
        check_pass "$agent_name found"
    fi
done

if [ $agent_count -eq 0 ]; then
    check_warn "No agents found"
fi

# Check git
echo
echo "Checking git..."
if [ -d "$WORKSPACE_DIR/.git" ]; then
    check_pass "Git repository initialized"
    
    cd "$WORKSPACE_DIR"
    if git diff --cached --quiet; then
        check_pass "No uncommitted staged changes"
    else
        check_warn "Staged changes not committed"
    fi
else
    check_fail "Not a git repository"
fi

# Summary
echo
echo "╔════════════════════════════════════════════════════════╗"
if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
    echo "║  ✅ All checks passed!                                 ║"
elif [ $errors -eq 0 ]; then
    echo "║  ⚠️  $warnings warning(s) — review above              ║"
else
    echo "║  ❌ $errors error(s), $warnings warning(s) — fix needed ║"
fi
echo "╚════════════════════════════════════════════════════════╝"
echo

exit $errors
