---
name: multiagency-add-agent
description: Add a new agent to the multiagency workspace. Use when asked to create a new agent, add an agent, or set up a new AI assistant with its own workspace and identity.
disable-model-invocation: true
user-invocable: true
---

# Add New Agent

Creates a new agent workspace from the kit template, registers it in OpenClaw, and optionally sets up Telegram and/or Discord routing.

## Sandbox Warning

`add-agent.sh` writes to the shared workspace root and to `~/.openclaw/openclaw.json`. Both paths are outside any individual agent's sandbox boundary, so the script will fail if your session is sandboxed.

- **`mode: "non-main"` (default):** main sessions are not sandboxed — no action needed.
- **`mode: "all"`:** your main session is sandboxed. Enable elevated exec in your gateway config (`tools.elevated.enabled: true`) and run `/elevated on` in this session before executing the script.

## Run

```bash
{baseDir}/scripts/add-agent.sh [agent-name]
```

The script will:
1. Prompt for an agent name (if not given as argument)
2. Copy `workspace-template` to `<workspace>/<agent-name>/`
3. Prompt to customize `IDENTITY.md` and `USER.md`
4. Prompt for sandbox mode (`inherit` or `off`) and register the agent in `openclaw.json`
5. Offer to run Telegram and/or Discord setup
6. Commit changes to git

After running, restart the gateway:

```bash
openclaw gateway restart
```

## Sandbox Modes

When prompted during creation:

- **`inherit`** (default) — the new agent follows `agents.defaults.sandbox.mode`. Under `"non-main"`, non-main sessions (Telegram, Discord, group chats, etc.) will be sandboxed; main sessions will not.
- **`off`** — the agent is never sandboxed, regardless of the global default. Use this for agents that need to write outside their workspace (e.g., another orchestration agent).

## Environment

- `WORKSPACE_DIR` — override the workspace root (default: auto-detected from script location)
- `OPENCLAW_DIR` — override the OpenClaw config directory (default: `~/.openclaw`)

## Change Agent Sandbox Mode

To update sandbox mode for an agent after creation:

```bash
{baseDir}/skills/multiagency-add-agent/scripts/set-agent-sandbox.sh --agent <agent-id> --mode <off|inherit>
```

Then restart the gateway:

```bash
openclaw gateway restart
```

- `off` — disables sandboxing for that agent
- `inherit` — removes the per-agent override; agent follows the global default again
