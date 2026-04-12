---
name: multiagency-discord-setup
description: Configure and manage Discord channel routing for OpenClaw agents. Use when asked to set up Discord for an agent, add a Discord bot, manage guilds/channels/allowlists, or route a Discord bot to an existing agent.
disable-model-invocation: true
user-invocable: true
---

# Discord Agent Setup & Management

## Sandbox Warning

Scripts in this skill write to `~/.openclaw/openclaw.json`, which is outside the agent sandbox boundary.

- **`mode: "non-main"` (default):** main sessions are not sandboxed — no action needed.
- **`mode: "all"`:** enable elevated exec (`tools.elevated.enabled: true`) and run `/elevated on` before executing.

## Overview

This skill provides the complete workflow for configuring an OpenClaw agent in a **multi-agent workspace** to receive messages from a Discord bot, and for managing the ongoing configuration of Discord accounts, guilds, channels, and allowlists.

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
4. **Store the bot token via the active secrets provider** (env/file/exec — never plaintext in config)
5. Configure the Discord account and binding in `openclaw.json`
6. Optionally create the agent workspace from template

## Add Guild (Server)

Configure an existing Discord bot account to respond in an additional server:

```bash
{baseDir}/scripts/setup-discord-guild.sh
```

Or with arguments:

```bash
{baseDir}/scripts/setup-discord-guild.sh --agent <agent-id> --account <account-id> --guild <server-id>
```

After running, restart the gateway:

```bash
openclaw gateway restart
```

## Managing Existing Bots

Use `manage-discord.sh` to view and modify Discord configuration after initial setup:

```bash
{baseDir}/scripts/manage-discord.sh <command> [options]
```

### List all accounts, guilds, and channels

```bash
{baseDir}/scripts/manage-discord.sh list
```

Output shows accounts, their SecretRef token types (never values), bound agents, guilds, user/role allowlists, channel restrictions, and mention settings.

### Manage user/role allowlists

```bash
# Show allowlists for all guilds on an account
{baseDir}/scripts/manage-discord.sh allowlist show --account dev

# Show for a specific guild
{baseDir}/scripts/manage-discord.sh allowlist show --account dev --guild 123456789012345678

# Add a user to a guild's allowlist
{baseDir}/scripts/manage-discord.sh allowlist add --guild 123456789012345678 --user 987654321098765432

# Add a role to a guild's allowlist
{baseDir}/scripts/manage-discord.sh allowlist add --guild 123456789012345678 --role 111111111111111111

# Remove a user
{baseDir}/scripts/manage-discord.sh allowlist remove --guild 123456789012345678 --user 987654321098765432
```

When only one Discord account exists, `--account` is auto-detected.

### Add or remove guilds (servers)

```bash
# Add a guild with mention required and user allowlist
{baseDir}/scripts/manage-discord.sh guild add --guild 123456789012345678 --require-mention true --users "987654321098765432"

# Add a guild where bot responds to all messages
{baseDir}/scripts/manage-discord.sh guild add --guild 123456789012345678 --require-mention false

# Remove a guild
{baseDir}/scripts/manage-discord.sh guild remove --guild 123456789012345678
```

### Restrict bot to specific channels

By default, a bot responds in all channels of an allowlisted guild. To restrict:

```bash
# Allow bot only in specific channels
{baseDir}/scripts/manage-discord.sh channel add --guild 123456789012345678 --channel 111111111111111111
{baseDir}/scripts/manage-discord.sh channel add --guild 123456789012345678 --channel 222222222222222222 --require-mention false

# List channels for a guild
{baseDir}/scripts/manage-discord.sh channel list --guild 123456789012345678

# Remove a channel restriction
{baseDir}/scripts/manage-discord.sh channel remove --guild 123456789012345678 --channel 111111111111111111
```

When `channels` is configured on a guild, **only listed channels are allowed**.

### Toggle require mention

```bash
# Require @mention in a guild
{baseDir}/scripts/manage-discord.sh mention on --guild 123456789012345678

# Allow bot to respond without @mention
{baseDir}/scripts/manage-discord.sh mention off --guild 123456789012345678

# Override for a specific channel
{baseDir}/scripts/manage-discord.sh mention off --guild 123456789012345678 --channel 111111111111111111
```

## Manual Workflow

### Step 1: Create Discord Application and Bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application** — name it something like "OpenClaw"
3. Click **Bot** on the sidebar, set the bot **Username**
4. Under **Privileged Gateway Intents**, enable:
   - **Message Content Intent** (required)
   - **Server Members Intent** (recommended; required for role allowlists)
5. Click **Reset Token** to generate your bot token — copy and save it
6. Click **OAuth2** on the sidebar, scroll to **OAuth2 URL Generator**:
   - Scopes: `bot`, `applications.commands`
   - Bot Permissions: View Channels, Send Messages, Read Message History, Embed Links, Attach Files
7. Copy the generated URL, open it in your browser, select your server, and authorize
8. Enable **Developer Mode** in Discord: User Settings → Advanced → Developer Mode
9. Right-click your **server icon** → **Copy Server ID**
10. Right-click your **own avatar** → **Copy User ID**

**Save your bot token, server ID, and user ID** — you'll need all three.

### Step 2: Store Bot Token via SecretRef

Bot tokens are **never stored as plaintext** in `openclaw.json`. They are stored via the active secrets provider and referenced by a SecretRef object.

The setup script handles this automatically. For manual setup:

```bash
# For env provider (default): store in ~/.openclaw/.env
echo 'export DISCORD_BOT_TOKEN_DEV="your-token"' >> ~/.openclaw/.env
chmod 600 ~/.openclaw/.env

# Write the SecretRef to config
openclaw config set channels.discord.accounts.dev.token \
  --ref-provider default --ref-source env --ref-id DISCORD_BOT_TOKEN_DEV

# Validate
openclaw secrets audit --check
```

For other providers (file, exec/vault), see [Secrets Management](https://github.com/openclaw/openclaw/blob/main/docs/gateway/secrets.md).

### Step 3: Edit openclaw.json

The resulting config uses SecretRef for the token:

```json
"channels": {
  "discord": {
    "enabled": true,
    "accounts": {
      "dev": {
        "enabled": true,
        "token": {
          "source": "env",
          "provider": "default",
          "id": "DISCORD_BOT_TOKEN_DEV"
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

Add a binding:

```json
"bindings": [
  {
    "agentId": "dev",
    "match": {
      "channel": "discord",
      "accountId": "dev"
    }
  }
]
```

### Step 4: Restart and Verify

```bash
openclaw secrets audit --check
openclaw gateway restart
```

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
| `guilds.<id>.channels` | No | Map of channel IDs; if set, only listed channels are allowed |
| `guilds.<id>.ignoreOtherMentions` | No | Drop messages that mention another user/role but not the bot |

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

## Channel-Level Allowlists

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

## Role-Based Agent Routing

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

## Security Notes

- **Bot tokens** must be stored via SecretRef — never as plaintext strings in `openclaw.json`
- The setup script uses the active secrets provider (env, file, or exec) automatically
- **guilds + users** restricts which servers and users can trigger the bot
- **requireMention: true** prevents the bot from responding to every message
- **`openclaw secrets audit --check`** verifies no plaintext residues remain
- Grant least-privilege Discord permissions (avoid Administrator)

## Troubleshooting

**Bot doesn't respond:**
- Gateway not restarted after config change
- Bot token SecretRef cannot resolve (run `openclaw secrets audit --check`)
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
