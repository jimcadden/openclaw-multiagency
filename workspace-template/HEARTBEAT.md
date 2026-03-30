# HEARTBEAT.md

Tasks to check on each heartbeat poll. Keep this file short — every line costs tokens.
Remove tasks that don't apply to your setup. Add your own below.

## Default Tasks

### Daily: Uncommitted Changes
Use the `multiagency-state-manager` skill to check for uncommitted changes.
If changes exist, commit them.

### Weekly: Kit Version
Check if the multiagency kit has a newer version available.
Run: `kit/skills/multiagency-kit-guide/scripts/check-kit-version.sh`
If an update is available, notify the user.

### Every Few Days: Memory Review
If `memory/` has accumulated daily notes that haven't been distilled:
Use the `multiagency-memory-manager` skill to review and update `MEMORY.md`.

---

## Your Tasks

<!-- Add your own periodic tasks here -->
<!-- Example: -->
<!-- ### Daily: Email Check -->
<!-- Check for urgent unread emails. -->
