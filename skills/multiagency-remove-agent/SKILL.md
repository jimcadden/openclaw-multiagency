---
name: multiagency-remove-agent
description: Remove an agent from the multiagency workspace. Use when asked to remove, delete, or decommission an agent. Handles openclaw.json cleanup, Telegram config removal, workspace archiving, and git commit.
disable-model-invocation: true
user-invocable: true
---

# Remove Agent

Safely removes an agent from the workspace. Archives the agent directory by default to prevent accidental data loss.

## Run

```bash
{baseDir}/scripts/remove-agent.sh <agent-name>
```

Options:
- `--delete` — permanently delete the workspace directory instead of archiving
- `--dry-run` — preview what will be removed without making changes

Always run `--dry-run` first when invoked by an agent.

## What It Does

1. Shows what will be removed (dry-run output)
2. Removes agent from `openclaw.json` agents.list
3. Removes Telegram account + binding from `openclaw.json` if present
4. Archives workspace to `<agent>.archived.YYYY-MM-DD/` (or deletes with `--delete`)
5. Commits the changes
6. Instructs to restart the gateway

## Telegram Note

This script removes the Telegram configuration from `openclaw.json` automatically. However, the **bot token remains active** until you delete the bot in Telegram:

1. Open Telegram and message **@BotFather**
2. Send `/deletebot`
3. Select the bot to delete
4. Confirm deletion

Do this after running the script to fully decommission the agent's Telegram presence.

## Recovering an Archived Agent

If you need to restore an archived agent:

```bash
cd <workspace>
mv <agent>.archived.YYYY-MM-DD <agent-name>
# Re-add to openclaw.json agents.list manually
openclaw gateway restart
```
