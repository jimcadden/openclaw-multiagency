---
name: multiagency-discord-setup
description: Configure Discord channel routing for an OpenClaw agent. Use when asked to set up Discord for an agent, add a Discord bot, or route a Discord bot to an existing agent.
disable-model-invocation: true
user-invocable: true
---

# Discord Agent Setup

## Sandbox Warning

Scripts in this skill write to `~/.openclaw/openclaw.json`, which is outside the agent sandbox boundary.

- **`mode: "non-main"` (default):** main sessions are not sandboxed — no action needed.
- **`mode: "all"`:** enable elevated exec (`tools.elevated.enabled: true`) and run `/elevated on` before executing.

## Overview

This skill provides the complete workflow for configuring an OpenClaw agent in a **multi-agent workspace** to receive messages from a Discord bot. The OpenClaw gateway handles the Discord connection — this skill writes the config that tells the gateway which bot token to use, which servers to join, and which agent to route messages to.

For full Discord channel documentation, see: https://github.com/openclaw/openclaw/blob/main/docs/channels/discord.md

## Quick Start

Run the interactive setup:

```bash
{baseDir}/scripts/setup-discord-agent.sh
```

This will:
1. Select or create an agent
2. Guide you through Discord bot creation in the Developer Portal
3. Collect your bot token, server ID, and user ID
4. Configure the Discord account and binding in `openclaw.json`
5. Optionally create the agent workspace from template

## Add Guild (Server)

Configure an existing Discord bot account to respond in an additional server:

```bash
{baseDir}/scripts/setup-discord-guild.sh
```

Or with arguments:

```bash
{baseDir}/scripts/setup-discord-guild.sh --agent <agent-id> --account <account-id> --guild <server-id>
```

The script will:
1. Select the agent and its Discord account (auto-detects if only one binding exists)
2. Add the guild to `channels.discord.accounts.<account>.guilds` with `requireMention` and user allowlist
3. Write the config directly to `openclaw.json`

After running, restart the gateway:

```bash
openclaw gateway restart
```

## Manual Workflow

### Step 1: Create Discord Application and Bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application** — name it something like "OpenClaw"
3. Click **Bot** on the sidebar, set the bot **Username**
4. Under **Privileged Gateway Intents**, enable:
   - **Message Content Intent** (required)
   - **Server Members Intent** (recommended)
5. Click **Reset Token** to generate your bot token — copy and save it
6. Click **OAuth2** on the sidebar, scroll to **OAuth2 URL Generator**:
   - Scopes: `bot`, `applications.commands`
   - Bot Permissions: View Channels, Send Messages, Read Message History, Embed Links, Attach Files
7. Copy the generated URL, open it in your browser, select your server, and authorize
8. Enable **Developer Mode** in Discord: User Settings → Advanced → Developer Mode
9. Right-click your **server icon** → **Copy Server ID**
10. Right-click your **own avatar** → **Copy User ID**

**Save your bot token, server ID, and user ID** — you'll need all three.

### Step 2: Plan Your Agent

| Value | Example | Notes |
|-------|---------|-------|
| `agentId` | `research` | Lowercase, hyphens OK |
| `accountId` | `research` | Discord account identifier |
| `workspace` | `<workspace>/research` | Agent's workspace directory |
| `model` | _(your preferred model)_ | Primary model for this agent |

### Step 3: Set Bot Token as Environment Variable

Discord bot tokens are stored as environment variable references (not plaintext) in `openclaw.json`. Export the token on the machine running OpenClaw:

```bash
export DISCORD_BOT_TOKEN="your-bot-token-here"
```

Add this to your shell profile (`.bashrc`, `.zshrc`, etc.) so it persists across restarts. If you run multiple Discord bots, use unique env var names (e.g., `DISCORD_RESEARCH_BOT_TOKEN`).

### Step 4: Edit openclaw.json

Open `~/.openclaw/openclaw.json` and add three sections:

#### 4a. Add Agent to `agents.list`

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

#### 4b. Add Discord Account to `channels.discord.accounts`

```json
"channels": {
  "discord": {
    "enabled": true,
    "accounts": {
      "research": {
        "enabled": true,
        "token": {
          "source": "env",
          "provider": "default",
          "id": "DISCORD_BOT_TOKEN"
        },
        "guilds": {
          "YOUR_SERVER_ID": {
            "requireMention": true,
            "users": ["YOUR_USER_ID"]
          }
        }
      }
    }
  }
}
```

**Key fields:**
- `enabled`: `true` to activate this account
- `token`: SecretRef pointing to the environment variable holding the bot token
- `guilds`: Map of server IDs to guild config
- `guilds.<id>.requireMention`: Whether the bot must be @mentioned to respond in channels
- `guilds.<id>.users`: Array of Discord user IDs allowed to trigger the bot

#### 4c. Add Binding

```json
"bindings": [
  {
    "agentId": "research",
    "match": {
      "channel": "discord",
      "accountId": "research"
    }
  }
]
```

This routes messages from the `research` Discord account to the `research` agent.

### Step 5: Create Workspace

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

### Step 6: Add to Git

```bash
cd <workspace>
git add your-agent-name/
git commit -m "[main] Add your-agent-name agent workspace"
git push origin main
```

### Step 7: Restart Gateway

```bash
openclaw gateway restart
```

Or use the gateway tool in your session:

```
gateway action=restart
```

### Step 8: Verify

1. Open Discord and find your bot (it should appear online in your server)
2. DM the bot or @mention it in a channel
3. The agent should respond

If it doesn't respond:
- Check gateway logs: `openclaw logs --follow`
- Verify the bot token env var is exported
- Verify **Message Content Intent** is enabled in the Developer Portal
- Confirm your server ID is in `guilds`
- Check the binding matches `agentId` and `accountId`

## Configuration Reference

### Discord Account Fields

| Field | Required | Description |
|-------|----------|-------------|
| `enabled` | No (default: true) | Enable/disable this account |
| `token` | Yes | SecretRef to bot token: `{ source: "env", provider: "default", id: "ENV_VAR" }` |
| `guilds` | No | Map of server IDs to guild config |
| `guilds.<id>.requireMention` | No (default: true) | Bot must be @mentioned to respond in channels |
| `guilds.<id>.users` | No | Array of Discord user IDs allowed to trigger the bot |
| `guilds.<id>.roles` | No | Array of Discord role IDs allowed to trigger the bot |

### Binding Fields

| Field | Required | Description |
|-------|----------|-------------|
| `agentId` | Yes | Target agent |
| `match.channel` | Yes | Channel type: `discord` |
| `match.accountId` | Yes | Discord account ID |

### Session Fields

| Field | Required | Description |
|-------|----------|-------------|
| `session.idleMinutes` | No (default: `10080`) | How long a session can be idle before expiring, in minutes. e.g. `30`, `720` (12h), `10080` (7d). Applies globally to all channels. |

## Guild Workspace Setup

Once DMs are working, you can set up your Discord server as a full workspace where each channel gets its own agent session. This is recommended for private servers.

### Require Mention vs. Always Respond

By default, `requireMention: true` means the bot only responds when @mentioned in channels. For a private server where it's just you and your bot, set `requireMention: false` to have it respond to every message:

```json
"guilds": {
  "YOUR_SERVER_ID": {
    "requireMention": false,
    "users": ["YOUR_USER_ID"]
  }
}
```

### Channel-Level Allowlists

Restrict the bot to specific channels within a server:

```json
"guilds": {
  "YOUR_SERVER_ID": {
    "requireMention": true,
    "channels": {
      "CHANNEL_ID_1": { "allow": true },
      "CHANNEL_ID_2": { "allow": true, "requireMention": false }
    }
  }
}
```

If `channels` is set, only listed channels are allowed. If omitted, all channels in the guild are allowed.

## Discord Channels and Threads

Each Discord guild channel and thread is routed as its own isolated session by OpenClaw. The session key uses the format `agent:{agentId}:discord:channel:{channelId}` — Discord threads are channels, so they follow the same pattern.

### How It Works

- Each Discord channel/thread gets its own session key and JSONL transcript in OpenClaw
- The agent workspace's `threads/` directory holds long-term memory per channel/thread
- On session start, the agent detects `:discord:channel:` in the `SESSION_KEY` and loads channel-specific memory

### Session Key Format

```
agent:{agentId}:discord:channel:{channelId}
```

Example: `agent:main:discord:channel:1489699841322909786`

**Sanitized folder name** (replace `:` with `-`):
```
agent-main-discord-channel-1489699841322909786
```

### Channel/Thread Memory

Memory files live in `threads/{sanitized-session-key}/MEMORY.md` within the agent workspace. They survive session expiry so the agent can resume context across restarts. The `threads/` directory name is a convention — it holds memory for any isolated session, including Discord channels.

See `multiagency-thread-memory` for the full thread memory protocol (creating folders, updating memory, session lifecycle).

## Common Patterns

### Multiple Bots, Same Agent

Route multiple Discord bots to one agent:

```json
"bindings": [
  {
    "agentId": "main",
    "match": {
      "channel": "discord",
      "accountId": "default"
    }
  },
  {
    "agentId": "main",
    "match": {
      "channel": "discord",
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
      "channel": "discord",
      "accountId": "research"
    }
  },
  {
    "agentId": "assistant",
    "match": {
      "channel": "discord",
      "accountId": "assistant"
    }
  }
]
```

### Role-Based Agent Routing

Route Discord guild members to different agents by role:

```json
"bindings": [
  {
    "agentId": "opus",
    "match": {
      "channel": "discord",
      "guildId": "YOUR_SERVER_ID",
      "roles": ["ROLE_ID"]
    }
  },
  {
    "agentId": "sonnet",
    "match": {
      "channel": "discord",
      "guildId": "YOUR_SERVER_ID"
    }
  }
]
```

## Troubleshooting

**Bot doesn't respond:**
- Gateway not restarted after config change
- Bot token env var not exported or incorrect
- **Message Content Intent** not enabled in Developer Portal
- Server ID not in `guilds`
- Binding doesn't match account ID

**Bot ignores channel messages but responds to DMs:**
- `requireMention: true` (default) — @mention the bot, or set to `false`
- Guild not in `guilds` allowlist
- `channels` allowlist configured but the channel is not listed

**Messages going to wrong agent:**
- Check binding order (first match wins)
- Verify `accountId` in binding matches Discord account
- Check role-based bindings if using `roles`

**Config validation errors:**
- JSON syntax (missing commas, quotes)
- Token must be a SecretRef object, not a plain string
- Use `gateway action=config.get` to verify current config

## Security Notes

- **Bot tokens** are sensitive — store in env vars, never plaintext in config
- **guilds + users** restricts which servers and users can trigger the bot
- **requireMention: true** prevents the bot from responding to every message
- Don't commit `openclaw.json` with real tokens to version control
- Grant least-privilege Discord permissions (avoid Administrator)
