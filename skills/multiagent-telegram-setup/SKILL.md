---
name: multiagent-telegram-setup
description: Set up a new OpenClaw agent with Telegram channel routing. Part of openclaw-multiagent kit. Use when creating a new agent identity that should receive Telegram messages, adding a new Telegram bot to route to an existing agent, configuring multi-agent setups where different Telegram bots route to different agents, or setting up specialized bots like research bot or assistant bot with dedicated workspaces and configurations.
---

# Telegram Agent Setup

## Overview

This skill provides the complete workflow for creating a new OpenClaw agent in a **multi-agent workspace** and configuring it to receive messages from a dedicated Telegram bot.

## Default: Multi-Agent Workspace

All new agents are created in `~/workspaces/` with shared skills and a standard template.

```
~/agent-workspace/
├── main/                   # Existing agents...
├── research/
└── your-new-agent/         ← Created from workspace.template
    ├── AGENTS.md
    ├── IDENTITY.md         # Customize this
    ├── MEMORY.md           # Customize this
    ├── SOUL.md
    ├── TOOLS.md            # Customize this
    ├── USER.md             # Customize this
    └── multiagent-state-manager -> ../shared/skills/multiagent-state-manager
```

## Quick Start

Run the interactive setup:

```bash
python3 ~/agent-workspace/kit/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py
```

This will:
1. Copy `workspace.template` to create your agent
2. Generate config snippets for `openclaw.json`
3. Guide you through Telegram bot creation
4. Remind you to commit the new workspace to git

## Manual Workflow

### Step 1: Create Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` command
3. Follow prompts:
   - **Name**: Display name (e.g., "Research Bot")
   - **Username**: Must end in `bot` (e.g., `my_research_bot`)
4. BotFather returns a token: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

**📝 Save this token** — you'll add it to the config.

### Step 2: Plan Your Agent

Decide on these values:

| Value | Example | Notes |
|-------|---------|-------|
| `agentId` | `research` | Lowercase, hyphens OK |
| `agentName` | `research` | Display name (optional) |
| `workspace` | `/root/.openclaw/workspace.research` | Agent's workspace directory |
| `agentDir` | `/root/.openclaw/agents/research` | Agent configuration directory |
| `accountId` | `research_bot` | Telegram account identifier |
| `model` | `rits-qwen3.5/Qwen/Qwen3.5-397B-A17B-FP8` | Primary model for this agent |

### Step 3: Edit openclaw.json

Open `~/.openclaw/openclaw.json` and add three sections:

#### 3a. Add Agent to `agents.list`

```json
"agents": {
  "list": [
    {
      "id": "main"
    },
    {
      "id": "research",
      "name": "research",
      "workspace": "/root/.openclaw/workspace.research",
      "agentDir": "/root/.openclaw/agents/research"
    }
  ]
}
```

#### 3b. Add Telegram Account to `channels.telegram.accounts`

```json
"channels": {
  "telegram": {
    "accounts": {
      "default": {
        "name": "jimclaw",
        "dmPolicy": "allowlist",
        "botToken": "__REDACTED__",
        "allowFrom": [YOUR_TELEGRAM_USER_ID],
        "groupPolicy": "allowlist",
        "streaming": "off"
      },
      "research_bot": {
        "enabled": true,
        "dmPolicy": "pairing",
        "botToken": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
        "allowFrom": [YOUR_TELEGRAM_USER_ID],
        "groupPolicy": "allowlist",
        "streaming": "partial"
      }
    }
  }
}
```

**Key fields:**
- `enabled`: `true` to activate this account
- `dmPolicy`: `pairing` routes based on bindings, `allowlist` uses `allowFrom`
- `botToken`: From BotFather
- `allowFrom`: Array of Telegram user IDs allowed to message this bot
- `streaming`: `off`, `partial`, or `full`

#### 3c. Add Binding

```json
"bindings": [
  {
    "agentId": "research",
    "match": {
      "channel": "telegram",
      "accountId": "research_bot"
    }
  }
]
```

This routes messages from the `research_bot` Telegram account to the `research` agent.

### Step 4: Create Workspace

```bash
cd ~/agent-workspace
cp -r workspace.template your-agent-name
```

The workspace holds the agent's files (IDENTITY.md, MEMORY.md, SOUL.md, etc.).

### Step 5: Add to Git

Commit the new workspace to version control:

```bash
cd ~/workspaces
git add your-agent-name/
git commit -m "[main] Add your-agent-name agent workspace"
git push origin main
```

### Step 6: Restart Gateway

```bash
openclaw gateway restart
```

Or use the gateway tool in your session:

```
gateway action=restart
```

### Step 7: Verify

1. Open Telegram and find your new bot
2. Send `/start`
3. The agent should respond

If it doesn't respond:
- Check gateway logs for errors
- Verify bot token is correct
- Confirm your user ID is in `allowFrom`
- Check the binding matches `agentId` and `accountId`

## Configuration Reference

### Agent Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique agent identifier |
| `name` | No | Display name |
| `workspace` | No | Defaults to main workspace if omitted |
| `agentDir` | No | Agent-specific config directory |

### Telegram Account Fields

| Field | Required | Description |
|-------|----------|-------------|
| `enabled` | No (default: true) | Enable/disable this account |
| `dmPolicy` | No (default: pairing) | `pairing` or `allowlist` |
| `botToken` | Yes | From BotFather |
| `allowFrom` | No | Array of allowed Telegram user IDs |
| `groupPolicy` | No (default: allowlist) | `allowlist` or `denylist` |
| `streaming` | No (default: off) | `off`, `partial`, or `full` |

### Binding Fields

| Field | Required | Description |
|-------|----------|-------------|
| `agentId` | Yes | Target agent |
| `match.channel` | Yes | Channel type (e.g., `telegram`) |
| `match.accountId` | Yes | Telegram account ID |

## Common Patterns

### Multiple Bots, Same Agent

Route multiple Telegram bots to one agent:

```json
"bindings": [
  {
    "agentId": "main",
    "match": {
      "channel": "telegram",
      "accountId": "default"
    }
  },
  {
    "agentId": "main",
    "match": {
      "channel": "telegram",
      "accountId": "personal_bot"
    }
  }
]
```

### Multiple Agents, Multiple Bots

Each bot routes to a different agent:

```json
"bindings": [
  {
    "agentId": "research",
    "match": {
      "channel": "telegram",
      "accountId": "research_bot"
    }
  },
  {
    "agentId": "assistant",
    "match": {
      "channel": "telegram",
      "accountId": "assistant_bot"
    }
  }
]
```

## Troubleshooting

**Bot doesn't respond:**
- Gateway not restarted after config change
- Bot token incorrect or expired
- User ID not in `allowFrom`
- Binding doesn't match account ID

**Messages going to wrong agent:**
- Check binding order (first match wins)
- Verify `accountId` in binding matches Telegram account
- Check `dmPolicy` setting

**Config validation errors:**
- JSON syntax (missing commas, quotes)
- JavaScript-style config needs manual editing
- Use `gateway action=config.get` to verify current config

## Security Notes

- **Bot tokens** are sensitive — treat like passwords
- **allowFrom** restricts who can message your bot — use it
- **groupPolicy: allowlist** prevents bot from joining random groups
- Don't commit `openclaw.json` with real tokens to version control
rol
