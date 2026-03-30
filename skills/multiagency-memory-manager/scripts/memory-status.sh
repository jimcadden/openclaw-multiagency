#!/bin/bash
#
# memory-status.sh: Show memory file inventory and distillation status
#
# Usage: ./memory-status.sh [workspace-dir]

set -euo pipefail

# ─── Resolve agent workspace ──────────────────────────────────────────────────

# Script lives at: <workspace>/kit/skills/multiagency-memory-manager/scripts/memory-status.sh
# Or accessed via shared/skills symlink. Either way, WORKSPACE_DIR or current dir is used.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${1:-}" ]; then
    AGENT_DIR="$1"
elif [ -n "${WORKSPACE_DIR:-}" ]; then
    AGENT_DIR="$WORKSPACE_DIR"
else
    # Try to find agent workspace: walk up until we find IDENTITY.md or SOUL.md
    AGENT_DIR="$(pwd)"
fi

MEMORY_DIR="$AGENT_DIR/memory"
MEMORY_MD="$AGENT_DIR/MEMORY.md"

# ─── Header ───────────────────────────────────────────────────────────────────

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Memory Status                                         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

# ─── MEMORY.md status ────────────────────────────────────────────────────────

echo "Long-term memory (MEMORY.md):"
if [ -f "$MEMORY_MD" ]; then
    LINE_COUNT=$(wc -l < "$MEMORY_MD" | tr -d ' ')
    LAST_MODIFIED=$(date -r "$MEMORY_MD" "+%Y-%m-%d" 2>/dev/null || stat -c "%y" "$MEMORY_MD" 2>/dev/null | cut -d' ' -f1)
    echo "  Last updated: $LAST_MODIFIED  ($LINE_COUNT lines)"

    # Warn if not updated in >7 days
    if command -v python3 &>/dev/null; then
        DAYS_SINCE=$(python3 -c "
from datetime import datetime, date
import os
mtime = os.path.getmtime('$MEMORY_MD')
days = (datetime.now() - datetime.fromtimestamp(mtime)).days
print(days)
" 2>/dev/null || echo "0")
        if [ "$DAYS_SINCE" -gt 7 ]; then
            echo "  ⚠  Not updated in ${DAYS_SINCE} days — consider distilling recent notes"
        fi
    fi
else
    echo "  ✗  MEMORY.md not found at $MEMORY_MD"
fi
echo

# ─── Daily memory files ───────────────────────────────────────────────────────

echo "Daily notes ($MEMORY_DIR/):"
if [ ! -d "$MEMORY_DIR" ]; then
    echo "  (no memory/ directory found)"
    echo
else
    # Count and list daily files (exclude archive/)
    DAILY_FILES=()
    while IFS= read -r -d '' f; do
        DAILY_FILES+=("$f")
    done < <(find "$MEMORY_DIR" -maxdepth 1 -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md" -print0 2>/dev/null | sort -z)

    if [ ${#DAILY_FILES[@]} -eq 0 ]; then
        echo "  (none)"
    else
        for f in "${DAILY_FILES[@]}"; do
            fname="$(basename "$f")"
            lines=$(wc -l < "$f" | tr -d ' ')
            printf "  %-30s  %4d lines\n" "$fname" "$lines"
        done
        echo
        echo "  Total: ${#DAILY_FILES[@]} daily file(s)"

        # Check for archived files
        ARCHIVE_COUNT=$(find "$MEMORY_DIR/archive" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$ARCHIVE_COUNT" -gt 0 ]; then
            echo "  Archived: $ARCHIVE_COUNT file(s) in memory/archive/"
        fi
    fi
    echo
fi

# ─── Recommendations ─────────────────────────────────────────────────────────

echo "────────────────────────────────────────────────────────"
if [ ${#DAILY_FILES[@]} -gt 7 ]; then
    echo "💡 ${#DAILY_FILES[@]} unarchived daily files — consider distilling into MEMORY.md"
    echo "   Use the multiagency-memory-manager skill for guided distillation."
elif [ ${#DAILY_FILES[@]} -gt 0 ]; then
    echo "✓  Memory looks healthy. ${#DAILY_FILES[@]} daily file(s) ready for review."
else
    echo "✓  No unarchived daily notes."
fi
echo
