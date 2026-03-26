#!/bin/bash
# reminder.sh - Check for uncommitted changes and remind user to commit
# Usage: ./reminder.sh [--auto-commit]
# Returns 0 if clean, 1 if uncommitted changes exist

# Detect workspace root
if [ -n "$WORKSPACE_DIR" ]; then
    DETECTED_WORKSPACE="$WORKSPACE_DIR"
else
    DETECTED_WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || echo "/home/claw/agent-workspace")
fi

cd "$DETECTED_WORKSPACE" || exit 1

# Detect agent name for multi-agent workspace
AGENT_NAME=""
CURRENT_DIR=$(pwd)
if [ -d "main" ] && [ -d "research" ] && [ -d "shared" ]; then
    case "$CURRENT_DIR" in
        */main) AGENT_NAME="main" ;;
        */research) AGENT_NAME="research" ;;
        */main-backup) AGENT_NAME="main-backup" ;;
        */dev) AGENT_NAME="dev" ;;
    esac
fi

# Check for uncommitted changes
UNCOMMITTED=$(git status --porcelain 2>/dev/null)
AHEAD=$(git rev-list --count HEAD@{upstream}..HEAD 2>/dev/null || echo "0")

if [ -z "$UNCOMMITTED" ] && [ "$AHEAD" -eq 0 ]; then
    echo "✓ Workspace clean. Nothing to commit."
    exit 0
fi

# Build reminder message
PREFIX=""
if [ -n "$AGENT_NAME" ]; then
    PREFIX="[$AGENT_NAME] "
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
printf "║  %s📝 Uncommitted changes detected%s                    ║\n" "$PREFIX" "$(printf '%*s' $((26 - ${#AGENT_NAME})) '')"
echo "╠════════════════════════════════════════════════════════════╣"

# Show changed files
if [ -n "$UNCOMMITTED" ]; then
    echo "║ Changed files:"
    git status --short | head -10 | while read line; do
        printf "║   %s%*s║\n" "${line:0:54}" $((54 - ${#line})) ""
    done
    COUNT=$(echo "$UNCOMMITTED" | wc -l)
    if [ "$COUNT" -gt 10 ]; then
        printf "║   ... and %d more files%*s║\n" "$((COUNT - 10))" $((31 - ${#COUNT})) ""
    fi
fi

# Show unpushed commits
if [ "$AHEAD" -gt 0 ]; then
    printf "║ Unpushed commits: %d%*s║\n" "$AHEAD" $((37 - ${#AHEAD})) ""
fi

echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Run: ./agent-state-manager/scripts/commit_workspace.sh    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

exit 1
