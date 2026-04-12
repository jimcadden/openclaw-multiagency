---
name: multiagency-telegram-setup
description: Configure Telegram channel routing for an OpenClaw agent. Use when asked to set up Telegram for an agent, add a Telegram bot, or route a Telegram bot to an existing agent.
disable-model-invocation: true
user-invocable: true
---

# Telegram Agent Setup

## Sandbox Warning

Scripts in this skill write to `~/.openclaw/openclaw.json`, which is outside the agent sandbox boundary.

- **`mode: "non-main"` (default):** main sessions are not sandboxed — no action needed.
- **`mode: "all"`:** enable elevated exec (`tools.elevated.enabled: true`) and run `/elevated on` before executing.

## Overview

This skill provides the complete workflow for creating a new OpenClaw agent in a **multi-agent workspace** and configuring it to receive messages from a dedicated Telegram bot.

## Default: Multi-Agent Workspace

All new agents are created in the workspace root with shared skills and a standard template.

```
<workspace>/
├── main/                   # Existing agents...
├── <new-agent>/            ← Created from kit/workspace-template
│   ├── AGENTS.md
│   ├── IDENTITY.md         # Customize this
│   ├── MEMORY.md           # Customize this
│   ├── SOUL.md
│   ├── TOOLS.md            # Customize this
│   ├── USER.md             # Customize this
│   └── multiagency-state-manager -> ../shared/skills/multiagency-state-manager
└── shared/
```

## Quick Start

Run the interactive setup:

```bash
{baseDir}/scripts/setup-telegram-agent.sh
```

This will:
1. Select or create an agent
2. Guide you through Telegram bot creation via BotFather
3. **Store the bot token via the active secrets provider** (env/file/exec — never plaintext in config)
4. Configure the Telegram account and binding in `openclaw.json`
5. Auto-detect your sender ID from existing Telegram accounts in the config
6. Optionally create the agent workspace from template

## Add Telegram Group

Configure an existing agent to receive messages from a dedicated Telegram group:

```bash
{baseDir}/scripts/setup-telegram-group.sh
```

Or with arguments:

```bash
{baseDir}/scripts/setup-telegram-group.sh --agent <agent-id> --account <account-id> --group <chat-id>
```

The script will:
1. Select the agent and its Telegram account (auto-detects if only one binding exists)
2. Add the group to `channels.telegram.groups` with `requireMention: false` and `groupPolicy: "open"`
3. Set account-level `groupPolicy: "allowlist"` and update `allowFrom` / `groupAllowFrom` with your sender ID
4. Write the config directly to `openclaw.json`

After running, add the bot to the Telegram group, promote it to admin, then restart:

```bash
openclaw gateway restart
```

If the bot misses messages, disable privacy mode in BotFather (`/setprivacy` -> Disable), then remove and re-add the bot to the group.

## Manual Workflow

### Step 1: Create Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send `/newbot` command
3. Follow prompts:
   - **Name**: Display name (e.g., "Research Bot")
   - **Username**: Must end in `bot` (e.g., `my_research_bot`)
4. BotFather returns a token: `123456789:ABCdefGHIjklMNOpqrsTUVwxyz`

**Save this token** — you'll store it via the secrets provider.

### Step 2: Store Bot Token via SecretRef

Bot tokens are **never stored as plaintext** in `openclaw.json`. They are stored via the active secrets provider and referenced by a SecretRef object.

The setup script handles this automatically. For manual setup:

```bash
# For env provider (default): store in ~/.openclaw/.env
echo 'export TELEGRAM_BOT_TOKEN_DEV="123456789:ABCdef..."' >> ~/.openclaw/.env
chmod 600 ~/.openclaw/.env

# Write the SecretRef to config
openclaw config set channels.telegram.accounts.dev_bot.botToken \
  --ref-provider default --ref-source env --ref-id TELEGRAM_BOT_TOKEN_DEV

# Validate
openclaw secrets audit --check
```

For other providers (file, exec/vault), see [Secrets Management](https://github.com/openclaw/openclaw/blob/main/docs/gateway/secrets.md).

### Step 3: Edit openclaw.json

The resulting config uses SecretRef for botToken:

#### 3a. Add Agent to `agents.list`

```json
"agents": {
  "list": [
    {
      "id": "main"
    },
    {
      "id": "research",
      "workspace": "<workspace>/research"
    }
  ]
}
```

#### 3b. Add Telegram Account to `channels.telegram.accounts`

> **Tip — reuse your existing sender ID:** If you already have a Telegram account configured (e.g., `default`), check its `allowFrom` array for your user ID and reuse the same value.

```json
"channels": {
  "telegram": {
    "accounts": {
      "research_bot": {
        "enabled": true,
        "dmPolicy": "pairing",
        "botToken": {
          "source": "env",
          "provider": "default",
          "id": "TELEGRAM_BOT_TOKEN_RESEARCH"
        },
        "allowFrom": [123456789],
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
- `botToken`: SecretRef to bot token — **never a plaintext string**
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

### Step 4: Create Workspace

Use `add-agent.sh` to create the workspace from the kit template (recommended):

```bash
cd <workspace>
./kit/scripts/add-agent.sh your-agent-name
```

### Step 5: Restart and Verify

```bash
openclaw secrets audit --check
openclaw gateway restart
```

1. Open Telegram and find your new bot
2. Send `/start`
3. The agent should respond

If it doesn't respond:
- Check gateway logs: `openclaw logs --follow`
- Verify SecretRef resolves: `openclaw secrets audit --check`
- Confirm your user ID is in `allowFrom`
- Check the binding matches `agentId` and `accountId`

## Configuration Reference

### Telegram Account Fields

| Field | Required | Description |
|-------|----------|-------------|
| `enabled` | No (default: true) | Enable/disable this account |
| `dmPolicy` | No (default: pairing) | `pairing` or `allowlist` |
| `botToken` | Yes | SecretRef: `{ source: "env", provider: "default", id: "ENV_VAR" }` |
| `allowFrom` | No | Array of allowed Telegram user IDs |
| `groupPolicy` | No (default: allowlist) | `allowlist` or `denylist` |
| `streaming` | No (default: off) | `off`, `partial`, or `full` |

### Binding Fields

| Field | Required | Description |
|-------|----------|-------------|
| `agentId` | Yes | Target agent |
| `match.channel` | Yes | Channel type (e.g., `telegram`) |
| `match.accountId` | Yes | Telegram account ID |

### Session Fields

| Field | Required | Description |
|-------|----------|-------------|
| `session.idleMinutes` | No (default: `10080`) | How long a session can be idle before expiring, in minutes. e.g. `30`, `720` (12h), `10080` (7d). Applies globally to all channels. |

## Forum Groups (Threads)

Telegram **forum supergroups** have multiple topic threads. OpenClaw treats each topic as a separate session automatically — but you need to configure the group to enable thread memory.

> **Important:** This only works with Telegram **forum supergroups** (`is_forum: true`). Regular groups with reply threads do NOT get separate sessions.

### Session Key Format

```
agent:{agentId}:telegram:{accountId}:group:{chatId}:topic:{topicId}
```

**Sanitized folder name** (replace `:` with `-`, strip leading `-` from negative chat IDs):
```
agent-main-telegram-your_bot-group-1001234567890-topic-123
```

See `multiagency-thread-memory` for the full thread memory protocol.

## Common Patterns

### Multiple Bots, Same Agent

Route multiple Telegram bots to one agent:

```json
"bindings": [
  {
    "agentId": "main",
    "match": { "channel": "telegram", "accountId": "default" }
  },
  {
    "agentId": "main",
    "match": { "channel": "telegram", "accountId": "personal_bot" }
  }
]
```

### Multiple Agents, Multiple Bots

Each bot routes to a different agent:

```json
"bindings": [
  {
    "agentId": "research",
    "match": { "channel": "telegram", "accountId": "research_bot" }
  },
  {
    "agentId": "assistant",
    "match": { "channel": "telegram", "accountId": "assistant_bot" }
  }
]
```

## Security Notes

- **Bot tokens** must be stored via SecretRef — never as plaintext strings in `openclaw.json`
- The setup script uses the active secrets provider (env, file, or exec) automatically
- **`openclaw secrets audit --check`** verifies no plaintext residues remain
- **allowFrom** restricts who can message your bot — use it
- **groupPolicy: allowlist** prevents bot from joining random groups

## Troubleshooting

**Bot doesn't respond:**
- Gateway not restarted after config change
- Bot token SecretRef cannot resolve (run `openclaw secrets audit --check`)
- User ID not in `allowFrom`
- Binding doesn't match account ID

**Messages going to wrong agent:**
- Check binding order (first match wins)
- Verify `accountId` in binding matches Telegram account
- Check `dmPolicy` setting
