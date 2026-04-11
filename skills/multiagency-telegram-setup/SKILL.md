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
1. Copy `workspace.template` to create your agent
2. Generate config snippets for `openclaw.json`
3. Auto-detect your sender ID from existing Telegram accounts in the config
4. Guide you through Telegram bot creation
5. Remind you to commit the new workspace to git

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

**📝 Save this token** — you'll add it to the config.

### Step 2: Plan Your Agent

Decide on these values:

| Value | Example | Notes |
|-------|---------|-------|
| `agentId` | `research` | Lowercase, hyphens OK |
| `agentName` | `research` | Display name (optional) |
| `workspace` | `<workspace>/research` | Agent's workspace directory |
| `agentDir` | `<openclaw-dir>/agents/research` | Agent configuration directory |
| `accountId` | `research_bot` | Telegram account identifier |
| `model` | _(your preferred model)_ | Primary model for this agent |

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
      "workspace": "<workspace>/research",
      "agentDir": "<openclaw-dir>/agents/research"
    }
  ]
}
```

#### 3b. Add Telegram Account to `channels.telegram.accounts`

> **Tip — reuse your existing sender ID:** If you already have a Telegram account configured (e.g., `default`), check its `allowFrom` array for your user ID and reuse the same value. This ensures the new bot only accepts DMs from you (1-to-1 pairing). If you don't have one yet, message `@userinfobot` on Telegram to get your numeric user ID.

```json
"channels": {
  "telegram": {
    "accounts": {
      "default": {
        "dmPolicy": "allowlist",
        "botToken": "<your-main-bot-token>",
        "allowFrom": [<your-telegram-user-id>],
        "groupPolicy": "allowlist",
        "streaming": "off"
      },
      "research_bot": {
        "enabled": true,
        "dmPolicy": "pairing",
        "botToken": "<your-research-bot-token>",
        "allowFrom": [<your-telegram-user-id>],
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
- `allowFrom`: Array of Telegram user IDs allowed to message this bot. **Check existing accounts in your config for a sender ID to reuse.**
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

Use `add-agent.sh` to create the workspace from the kit template (recommended):

```bash
cd <workspace>
./kit/scripts/add-agent.sh your-agent-name
```

Or manually:

```bash
cd <workspace>
cp -r kit/workspace-template your-agent-name
```

The workspace holds the agent's files (IDENTITY.md, MEMORY.md, SOUL.md, etc.).

### Step 5: Add to Git

Commit the new workspace to version control:

```bash
cd <workspace>
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

### Session Fields

| Field | Required | Description |
|-------|----------|-------------|
| `session.idleMinutes` | No (default: `10080`) | How long a session can be idle before expiring, in minutes. e.g. `30`, `720` (12h), `10080` (7d). Applies globally to all channels. |

## Forum Groups (Threads)

Telegram **forum supergroups** have multiple topic threads. OpenClaw treats each topic as a separate session automatically — but you need to configure the group to enable thread memory.

> **Important:** This only works with Telegram **forum supergroups** (`is_forum: true`). Regular groups with reply threads do NOT get separate sessions — OpenClaw intentionally ignores `message_thread_id` for non-forum groups, because reply threads in regular groups are not persistent topics. All messages in a regular group share one session key.
>
> To use topic threads, your Telegram group must have **Topics** enabled: Group Settings → Topics → Enable.

### How It Works

- Each forum topic gets its own session key and JSONL transcript in OpenClaw
- The agent workspace's `threads/` directory holds long-term memory per thread
- On session start, the agent identifies its thread and loads thread-specific memory

### Step 1: Enable the Bot in Your Forum Group

1. Add your bot to the Telegram forum group
2. Promote it to admin (needed to read messages in topics)
3. Find your group's chat ID (use `@userinfobot` or check gateway logs)

### Step 2: Add Group to allowGroups in openclaw.json

Add the group to your Telegram account config:

```json
"channels": {
  "telegram": {
    "accounts": {
      "your_bot": {
        "enabled": true,
        "botToken": "<token>",
        "allowFrom": [<your-user-id>],
        "groupPolicy": "allowlist",
        "allowGroups": [-1001234567890],
        "streaming": "partial",
        "groups": {
          "-1001234567890": {
            "systemPrompt": "You are in a Telegram forum group. Each topic thread is a separate long-running conversation with its own memory."
          }
        }
      }
    }
  }
}
```

### Step 3: Inject Session Keys via Per-Topic System Prompts

This is the critical step for thread memory. Each topic's system prompt injects its session key so the agent can find its memory folder deterministically — no guessing required:

```json
"groups": {
  "-1001234567890": {
    "systemPrompt": "You are in a Telegram forum group. Each topic thread is a separate long-running conversation with its own memory.",
    "topics": {
      "123": {
        "systemPrompt": "SESSION_KEY: agent:main:telegram:your_bot:group:-1001234567890:topic:123\nTopic: Health & Fitness"
      },
      "456": {
        "systemPrompt": "SESSION_KEY: agent:main:telegram:your_bot:group:-1001234567890:topic:456\nTopic: Home Renovation"
      }
    }
  }
}
```

The agent reads `SESSION_KEY` from the system prompt, sanitizes it (`:` → `-`, strip leading `-` from chat ID), and uses it directly as its thread folder path: `threads/{session-key}/MEMORY.md`.

**Session key format:**
```
agent:{agentId}:telegram:{accountId}:group:{chatId}:topic:{topicId}
```

**Sanitized folder name** (replace `:` with `-`, strip leading `-` from negative chat IDs):
```
agent-main-telegram-your_bot-group-1001234567890-topic-123
```

### Step 4: Initialize Thread Folders

When the agent first encounters a new thread topic, it creates the thread folder automatically. You can also pre-create them:

```bash
mkdir -p <workspace>/threads/agent-main-telegram-your_bot-group-1001234567890-topic-123
# Then create MEMORY.md from the template in threads/README.md
```

### Finding Group and Topic IDs

**Group chat ID:** Check OpenClaw gateway logs when a message arrives from the group. Look for `chatId` or the peer id in the routing output.

**Topic IDs:** Check gateway logs for `messageThreadId` or `resolvedThreadId` when a message arrives from a specific topic.

**Tip:** Send a test message to each topic and check gateway logs immediately — you'll see the full session key being assigned. Copy it directly into your `openclaw.json` topic config.

---

## Session Timeout

OpenClaw assigns each conversation context (DM, group, forum topic, Discord thread) its own session. Sessions expire after a configurable idle period — when that happens, the transcript resets and the agent starts fresh with no memory of the prior conversation.

### Default Behavior

Without explicit configuration, sessions may expire in as little as 24 hours of inactivity. For forum topics and Discord threads that are meant to be long-running conversations, this is too aggressive.

### Configuration

The multiagency kit sets a generous default of `10080` (7 days) during setup. You can adjust it in `openclaw.json`:

```json
"session": {
  "idleMinutes": 10080
}
```

The value is an integer number of minutes. e.g. `30` (30 min), `720` (12 h), `10080` (7 d). This is a global setting — it applies to all sessions across all channels (Telegram DMs, groups, forum topics, Discord channels, Discord threads).

### Why Thread Memory Matters

Even with a generous timeout, sessions **will** eventually expire. Thread memory (`threads/{session-key}/MEMORY.md`) is the mechanism that bridges session boundaries for long-running conversations. When a session expires and restarts, the agent reloads its thread memory and picks up where it left off.

Without thread memory, session expiry means total amnesia. With it, the agent retains context across any number of session restarts.

See `multiagency-thread-memory` for the full thread memory protocol.

---

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
