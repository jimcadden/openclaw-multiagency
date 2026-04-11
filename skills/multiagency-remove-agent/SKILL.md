---
name: multiagency-remove-agent
description: Remove an agent from the multiagency workspace. Use when asked to remove, delete, or decommission an agent. Handles openclaw.json cleanup, Telegram/Discord config removal, workspace archiving, and git commit.
disable-model-invocation: true
user-invocable: true
---

# Remove Agent

Safely removes an agent from the workspace. Archives the agent directory by default to prevent accidental data loss.

## Sandbox Warning

This script writes to `~/.openclaw/openclaw.json` and modifies directories at the shared workspace root. Both are outside the agent sandbox boundary.

- **`mode: "non-main"` (default):** main sessions are not sandboxed — no action needed.
- **`mode: "all"`:** enable elevated exec (`tools.elevated.enabled: true`) and run `/elevated on` before executing.

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
3. Removes Telegram/Discord account + binding from `openclaw.json` if present
4. Archives workspace to `<agent>.archived.YYYY-MM-DD/` (or deletes with `--delete`)
5. Commits the changes
6. Instructs to restart the gateway

## Channel Cleanup Notes

This script removes channel configuration (Telegram accounts, Discord accounts, bindings) from `openclaw.json` automatically. However, the **bot tokens remain active** until you revoke them at the source.

### Telegram

1. Open Telegram and message **@BotFather**
2. Send `/deletebot`
3. Select the bot to delete
4. Confirm deletion

### Discord

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Select the application
3. Under **Bot**, click **Reset Token** (to invalidate the old token) or delete the application entirely

Do this after running the script to fully decommission the agent's channel presence.

## Recovering an Archived Agent

If you need to restore an archived agent:

```bash
cd <workspace>
mv <agent>.archived.YYYY-MM-DD <agent-name>
# Re-add to openclaw.json agents.list manually
openclaw gateway restart
```
