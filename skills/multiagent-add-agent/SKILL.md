---
name: multiagent-add-agent
description: Add a new agent to the multiagent workspace. Use when asked to create a new agent, add an agent, or set up a new AI assistant with its own workspace and identity.
disable-model-invocation: true
user-invocable: true
---

# Add New Agent

Creates a new agent workspace from the kit template, registers it in OpenClaw, and optionally sets up Telegram routing.

## Run

```bash
{baseDir}/scripts/add-agent.sh [agent-name]
```

The script will:
1. Prompt for an agent name (if not given as argument)
2. Copy `workspace-template` to `<workspace>/<agent-name>/`
3. Prompt to customize `IDENTITY.md` and `USER.md`
4. Register the agent in `openclaw.json` agents.list
5. Offer to run Telegram setup
6. Commit changes to git

After running, restart the gateway:

```bash
openclaw gateway restart
```

## Environment

- `WORKSPACE_DIR` — override the workspace root (default: auto-detected from script location)
- `OPENCLAW_DIR` — override the OpenClaw config directory (default: `~/.openclaw`)
