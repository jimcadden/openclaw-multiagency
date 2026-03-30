---
name: multiagency-memory-manager
description: Review and distill agent memory. Use when asked to update long-term memory, clean up daily notes, review recent session history, or when memory files have not been distilled recently.
disable-model-invocation: true
user-invocable: true
---

# Memory Manager

Keeps your memory files healthy: distill daily notes into long-term memory, commit changes, and clean up what's no longer needed.

## Check Memory Status

Run this first to see the current state of your memory files:

```bash
{baseDir}/scripts/memory-status.sh
```

This shows:
- All `memory/YYYY-MM-DD.md` files with line counts
- Date of last `MEMORY.md` update
- Warning if daily notes have not been distilled in more than 7 days

## Distillation Process

1. **Run the status check** — identify which daily files have not been processed
2. **Read recent daily files** — `memory/YYYY-MM-DD.md` for the past 7–14 days
3. **Identify what matters** — decisions made, lessons learned, important context, things to remember long-term
4. **Update `MEMORY.md`** — add distilled entries; prune entries that are no longer relevant
5. **Archive processed daily files** — move old files to `memory/archive/` once distilled:
   ```bash
   mkdir -p memory/archive
   mv memory/2025-*.md memory/archive/  # adjust date range as needed
   ```
6. **Commit** — use `multiagency-state-manager` to commit the updated memory files

## What Belongs in MEMORY.md

Keep:
- Decisions and their reasoning
- Preferences and patterns you've learned about your user
- Ongoing project context
- Lessons from mistakes
- Things explicitly asked to remember

Prune:
- Completed tasks with no lasting context
- Outdated project state
- Duplicate or redundant entries

## What Belongs in Daily Files

Daily `memory/YYYY-MM-DD.md` files are raw session logs — what happened, what was discussed, what tasks were done. They feed into MEMORY.md over time. Keep them brief and factual.

## When to Run

- When MEMORY.md hasn't been updated in several days
- When `memory/` has accumulated many unprocessed daily files
- When the user asks you to "update your memory" or "review recent sessions"
- During a quiet heartbeat when no urgent tasks are pending
