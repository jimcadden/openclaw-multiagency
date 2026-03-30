#!/bin/bash
#
# check-kit-version.sh: Check if the kit submodule is up to date
#
# Usage: ./check-kit-version.sh [workspace-dir]
# Returns: 0 if up to date, 1 if update available or error

set -euo pipefail

WORKSPACE_DIR="${1:-${WORKSPACE_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.openclaw/workspace")}}"
KIT_DIR="$WORKSPACE_DIR/kit"

if [ ! -d "$KIT_DIR" ]; then
    echo "✗  Kit directory not found at $KIT_DIR"
    exit 1
fi

if [ ! -d "$KIT_DIR/.git" ] && [ ! -f "$KIT_DIR/.git" ]; then
    echo "✗  Kit is not a git repository"
    exit 1
fi

cd "$KIT_DIR"

CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

if [ -z "$CURRENT_TAG" ]; then
    echo "⚠  Kit is not pinned to a release tag (at $CURRENT_COMMIT)"
    echo "   Run update-kit.sh to pin to a stable release."
    exit 1
fi

# Fetch latest tags (quiet, non-fatal)
if ! git fetch --tags --quiet 2>/dev/null; then
    echo "⚠  Could not reach remote to check for updates (offline?)"
    echo "   Current version: $CURRENT_TAG"
    exit 0
fi

LATEST_TAG=$(git tag -l | sort -V | tail -1)

if [ -z "$LATEST_TAG" ]; then
    echo "⚠  No release tags found on remote"
    echo "   Current version: $CURRENT_TAG"
    exit 0
fi

if [ "$CURRENT_TAG" = "$LATEST_TAG" ]; then
    echo "✓  Kit is up to date ($CURRENT_TAG)"
    exit 0
else
    echo "↑  Kit update available: $CURRENT_TAG → $LATEST_TAG"
    echo "   To update, use the multiagency-kit-guide skill:"
    echo "   Run: {baseDir}/scripts/update-kit.sh"
    exit 1
fi
