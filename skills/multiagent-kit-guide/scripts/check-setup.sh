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
if [ -L "$WORKSPACE_DIR/shared/skills/multiagent-state-manager" ]; then
    check_pass "multiagent-state-manager symlink exists"
else
    check_fail "multiagent-state-manager symlink missing"
fi

if [ -L "$WORKSPACE_DIR/shared/skills/multiagent-telegram-setup" ]; then
    check_pass "multiagent-telegram-setup symlink exists"
else
    check_fail "multiagent-telegram-setup symlink missing"
fi

# Check agents
echo
echo "Checking agents..."
agent_count=0
for dir in "$WORKSPACE_DIR"/*/; do
    if [ -f "$dir/IDENTITY.md" ] && [ -f "$dir/SOUL.md" ]; then
        agent_name=$(basename "$dir")
        ((agent_count++))
        
        missing=0
        [ -L "$dir/multiagent-state-manager" ] || ((missing++))
        [ -L "$dir/multiagent-telegram-setup" ] || ((missing++))
        
        if [ $missing -eq 0 ]; then
            check_pass "$agent_name"
        else
            check_fail "$agent_name (missing symlinks)"
        fi
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
