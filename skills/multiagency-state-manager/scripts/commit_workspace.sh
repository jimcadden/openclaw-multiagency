#!/bin/bash
# commit_workspace.sh - Stage and commit workspace changes with smart message
# Usage: ./commit_workspace.sh ["custom message"]
# Supports multi-agent workspace: auto-detects agent from current directory

# ─── Resolve workspace root ───────────────────────────────────────────────────

if [ -n "$WORKSPACE_DIR" ]; then
    DETECTED_WORKSPACE="$WORKSPACE_DIR"
else
    # Walk up to find git root
    DETECTED_WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi

if [ -z "$DETECTED_WORKSPACE" ]; then
    echo "Could not detect workspace root. Set WORKSPACE_DIR or run from within a git repo."
    exit 1
fi

cd "$DETECTED_WORKSPACE" || exit 1

# ─── Detect agent name ────────────────────────────────────────────────────────

AGENT_NAME=""
IS_MULTI_AGENT=false

# Multi-agent layout: workspace root contains shared/ and at least one agent dir
if [ -d "shared" ] && [ -d "shared/skills" ]; then
    IS_MULTI_AGENT=true
    # Derive agent name from current directory name if we're inside an agent subdir
    CURRENT_DIR=$(pwd)
    PARENT=$(dirname "$CURRENT_DIR")
    BASENAME=$(basename "$CURRENT_DIR")
    if [ "$PARENT" = "$DETECTED_WORKSPACE" ] && [ "$BASENAME" != "shared" ] && [ "$BASENAME" != "kit" ]; then
        AGENT_NAME="$BASENAME"
    fi
fi

# ─── Verify git repo ──────────────────────────────────────────────────────────

if [ ! -d ".git" ]; then
    echo "Not a git repository. Please initialize first."
    exit 1
fi

# ─── Stage files ─────────────────────────────────────────────────────────────

echo "Staging workspace changes..."
if $IS_MULTI_AGENT; then
    git add -A
else
    git add MEMORY.md memory/*.md USER.md IDENTITY.md SOUL.md TOOLS.md AGENTS.md HEARTBEAT.md 2>/dev/null || true
fi

# ─── Check for changes ────────────────────────────────────────────────────────

if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 0
fi

# ─── Build commit message ────────────────────────────────────────────────────

if [ -n "${2:-}" ]; then
    MESSAGE="$2"
else
    CHANGED=$(git diff --cached --name-only | grep -E '\.(md|txt|json)$' | head -5 | tr '\n' ' ')
    TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M UTC")
    MESSAGE="Session checkpoint $TIMESTAMP - $CHANGED"
fi

if [ -n "$AGENT_NAME" ]; then
    MESSAGE="[$AGENT_NAME] $MESSAGE"
fi

# ─── Build footer with OpenClaw version + model ──────────────────────────────

OC_CONFIG="${OPENCLAW_DIR:-$HOME/.openclaw}/openclaw.json"
OPENCLAW_VERSION=""
MODEL=""

if command -v openclaw &>/dev/null; then
    OPENCLAW_VERSION=$(openclaw version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
fi

if [ -z "$OPENCLAW_VERSION" ] && [ -f "$OC_CONFIG" ]; then
    OPENCLAW_VERSION=$(grep -oE '"lastTouchedVersion":\s*"[^"]+"' "$OC_CONFIG" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
fi

if [ -n "${OPENCLAW_MODEL:-}" ]; then
    MODEL="$OPENCLAW_MODEL"
elif [ -f "$OC_CONFIG" ]; then
    MODEL=$(grep -oE '"primary":\s*"[^"]+"' "$OC_CONFIG" 2>/dev/null \
        | head -1 | grep -oE '[^"]+/[^"]+' | tail -1 || true)
fi

FULL_MESSAGE="${MESSAGE}"
if [ -n "$OPENCLAW_VERSION" ] || [ -n "$MODEL" ]; then
    FULL_MESSAGE="${MESSAGE}

OpenClaw: ${OPENCLAW_VERSION:-unknown}
Model: ${MODEL:-unknown}"
fi

# ─── Commit ───────────────────────────────────────────────────────────────────

git commit -m "$FULL_MESSAGE"
echo "Committed: $MESSAGE"

# ─── Auto-push if remote configured ──────────────────────────────────────────

if git remote get-url origin &>/dev/null; then
    echo "Pushing to origin..."
    git push origin HEAD
else
    echo "No remote configured. To push: git remote add origin <url> && git push -u origin main"
fi

git status --short
