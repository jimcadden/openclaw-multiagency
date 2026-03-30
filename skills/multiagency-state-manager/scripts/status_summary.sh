#!/bin/bash
# status_summary.sh - Show human-readable workspace git status
# Usage: ./status_summary.sh [workspace_path]

WORKSPACE="${1:-$WORKSPACE_DIR}"
if [ -z "$WORKSPACE" ]; then
    WORKSPACE=$(cd "$(dirname "$0")/../.." && pwd)
fi

cd "$WORKSPACE" || exit 1

# Detect if multi-agent workspace and which agent we're in
AGENT_NAME=""
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$GIT_ROOT" ]; then
    # Check if this is multi-agent workspace (has main, research, shared subdirs)
    if [ -d "$GIT_ROOT/main" ] && [ -d "$GIT_ROOT/research" ] && [ -d "$GIT_ROOT/shared" ]; then
        # We're in a multi-agent workspace, detect which agent based on current dir
        CURRENT_ABS=$(pwd)
        case "$CURRENT_ABS" in
            */main|*/main/*) AGENT_NAME="main" ;;
            */research|*/research/*) AGENT_NAME="research" ;;
            */main-backup|*/main-backup/*) AGENT_NAME="main-backup" ;;
            */dev|*/dev/*) AGENT_NAME="dev" ;;
        esac
    fi
fi

if [ ! -d ".git" ] && [ ! -d "$GIT_ROOT/.git" ]; then
    echo "Not a git repository. Run commit_workspace.sh to initialize."
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Workspace State                                           ║"
echo "╠════════════════════════════════════════════════════════════╣"

# Show agent name if in multi-agent mode
if [ -n "$AGENT_NAME" ]; then
    printf "║  🤖 Agent: %-47s ║\n" "$AGENT_NAME"
    echo "╠════════════════════════════════════════════════════════════╣"
fi

# Uncommitted changes
echo "║  📝 Uncommitted changes:                                   ║"
echo "╠════════════════════════════════════════════════════════════╣"

CHANGED_FILES=$(git status --short 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
    echo "║    (none)                                                  ║"
else
    echo "$CHANGED_FILES" | head -10 | while IFS= read -r line; do
        printf "║    %-55s ║\n" "${line:0:55}"
    done
    TOTAL=$(echo "$CHANGED_FILES" | wc -l)
    if [ "$TOTAL" -gt 10 ]; then
        echo "║    ... and $((TOTAL - 10)) more files                          ║"
    fi
fi

echo "╠════════════════════════════════════════════════════════════╣"
echo "║  📋 Recent commits:                                        ║"
echo "╠════════════════════════════════════════════════════════════╣"

git log --oneline -5 --decorate 2>/dev/null | while IFS= read -r line; do
    printf "║    %-55s ║\n" "${line:0:55}"
done

echo "╠════════════════════════════════════════════════════════════╣"
echo "║  🌐 Remote status:                                         ║"
echo "╠════════════════════════════════════════════════════════════╣"

REMOTE=$(git remote -v 2>/dev/null)
if [ -z "$REMOTE" ]; then
    echo "║    (no remote configured)                                  ║"
    echo "║                                                            ║"
    echo "║    To setup:                                               ║"
    echo "║    git remote add origin <your-repo-url>                   ║"
else
    echo "║    $(printf '%-55s' "$(echo "$REMOTE" | head -1)") ║"
    
    UNPUSHED=$(git log --oneline --branches --not --remotes 2>/dev/null | wc -l)
    if [ "$UNPUSHED" -gt 0 ]; then
        echo "╠════════════════════════════════════════════════════════════╣"
        printf "║  ⚠️  Unpushed commits: %-36s ║\n" "$UNPUSHED"
    fi
    
    # Check if behind remote
    git fetch --quiet 2>/dev/null
    BEHIND=$(git log --oneline HEAD..origin/$(git branch --show-current) 2>/dev/null | wc -l)
    if [ "$BEHIND" -gt 0 ]; then
        echo "╠════════════════════════════════════════════════════════════╣"
        printf "║  ⬇️  Behind remote by: %-36s ║\n" "$BEHIND commits"
    fi
fi

echo "╚════════════════════════════════════════════════════════════╝"

# Show commit suggestion
if [ -n "$CHANGED_FILES" ]; then
    echo ""
    echo "💡 To commit: ./scripts/commit_workspace.sh [\"message\"]"
fi
