#!/bin/bash
# reminder.sh - Check for uncommitted changes and remind user to commit
# Usage: ./reminder.sh
# Returns 0 if clean, 1 if uncommitted changes exist

# ─── Resolve workspace root ───────────────────────────────────────────────────

if [ -n "$WORKSPACE_DIR" ]; then
    DETECTED_WORKSPACE="$WORKSPACE_DIR"
else
    DETECTED_WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi

if [ -z "$DETECTED_WORKSPACE" ]; then
    echo "Could not detect workspace root. Set WORKSPACE_DIR or run from within a git repo."
    exit 1
fi

cd "$DETECTED_WORKSPACE" || exit 1

# ─── Detect agent name ────────────────────────────────────────────────────────

AGENT_NAME=""

# Multi-agent layout: workspace root contains shared/ and shared/skills/
if [ -d "shared" ] && [ -d "shared/skills" ]; then
    CURRENT_DIR=$(pwd)
    PARENT=$(dirname "$CURRENT_DIR")
    BASENAME=$(basename "$CURRENT_DIR")
    if [ "$PARENT" = "$DETECTED_WORKSPACE" ] && [ "$BASENAME" != "shared" ] && [ "$BASENAME" != "kit" ]; then
        AGENT_NAME="$BASENAME"
    fi
fi

# ─── Check for uncommitted changes ───────────────────────────────────────────

UNCOMMITTED=$(git status --porcelain 2>/dev/null)
AHEAD=$(git rev-list --count HEAD@{upstream}..HEAD 2>/dev/null || echo "0")

if [ -z "$UNCOMMITTED" ] && [ "$AHEAD" -eq 0 ]; then
    echo "✓ Workspace clean. Nothing to commit."
    exit 0
fi

# ─── Print reminder ───────────────────────────────────────────────────────────

PREFIX=""
if [ -n "$AGENT_NAME" ]; then
    PREFIX="[$AGENT_NAME] "
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
printf "║  %s📝 Uncommitted changes detected                         ║\n" "$PREFIX"
echo "╠════════════════════════════════════════════════════════════╣"

if [ -n "$UNCOMMITTED" ]; then
    echo "║ Changed files:"
    echo "$UNCOMMITTED" | head -10 | while IFS= read -r line; do
        printf "║   %-54s ║\n" "${line:0:54}"
    done
    COUNT=$(echo "$UNCOMMITTED" | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 10 ]; then
        printf "║   ... and %d more files%*s║\n" "$((COUNT - 10))" $((31 - ${#COUNT})) ""
    fi
fi

if [ "$AHEAD" -gt 0 ]; then
    printf "║ Unpushed commits: %-38s ║\n" "$AHEAD"
fi

echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Run: ./multiagency-state-manager/scripts/commit_workspace.sh ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

exit 1
