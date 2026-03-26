#!/bin/bash
#
# update-kit.sh: Interactive kit updater
#
# Usage: ./update-kit.sh
#

set -e

WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspaces}"
KIT_DIR="$WORKSPACE_DIR/kit"

echo "╔════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Multi-Agent Kit Updater                      ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

cd "$WORKSPACE_DIR"

# Check current version
echo "Current kit status:"
cd "$KIT_DIR"
current_version=$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)
echo "  Version: $current_version"
echo "  Branch: $(git branch --show-current 2>/dev/null || echo 'detached')"
echo

# Fetch latest tags
echo "Fetching available versions..."
git fetch --tags

echo
echo "Available versions:"
git tag -l | sort -V | tail -10
echo

# Ask for version
read -p "Enter version to update to (or 'latest' for newest): " target_version

if [ "$target_version" = "latest" ]; then
    target_version=$(git tag -l | sort -V | tail -1)
    echo "Latest version: $target_version"
fi

# Validate version exists
if ! git tag -l | grep -q "^${target_version}$"; then
    echo "❌ Version '$target_version' not found"
    exit 1
fi

# Show changes
echo
echo "Changes from $current_version to $target_version:"
git log --oneline "${current_version}..${target_version}" 2>/dev/null || echo "  (will show after checkout)"

echo
read -p "Proceed with update? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Perform update
echo
echo "Updating kit to $target_version..."
git checkout "$target_version"
echo "✅ Kit updated"

cd "$WORKSPACE_DIR"
echo
echo "Staging changes..."
git add kit

echo
echo "Git status:"
git status --short

echo
read -p "Commit this update? [Y/n] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    git commit -m "[main] Update kit to $target_version"
    echo "✅ Committed"
    echo
    echo "Next steps:"
    echo "  1. Test: openclaw gateway status"
    echo "  2. Push: git push origin main"
else
    echo "Changes staged but not committed."
    echo "Run 'git commit' when ready."
fi
