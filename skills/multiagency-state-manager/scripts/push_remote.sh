#!/bin/bash
# push_remote.sh - Push commits to GitHub remote
# Usage: ./push_remote.sh [remote] [branch]

WORKSPACE="${1:-/home/claw/.openclaw/workspace}"
cd "$WORKSPACE" || exit 1

REMOTE="${2:-origin}"
BRANCH="${3:-main}"

if [ ! -d ".git" ]; then
    echo "Not a git repository. Run commit_workspace.sh first."
    exit 1
fi

echo "Pushing to $REMOTE/$BRANCH..."
git push -u "$REMOTE" "$BRANCH"

if [ $? -eq 0 ]; then
    echo "✓ Pushed successfully"
else
    echo "✗ Push failed. Check remote configuration and credentials."
    exit 1
fi
