#!/bin/bash
#
# setup-discord-agent.sh: Set up Discord bot routing for an OpenClaw agent
#
# Usage: ./setup-discord-agent.sh [--agent <agent-id>]
#
# Walks through:
#   1. Selecting or creating an agent
#   2. Creating a Discord bot via the Developer Portal
#   3. Configuring the Discord account and binding in openclaw.json
#   4. Optionally creating the agent workspace from template

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }
log_step()    { echo; echo -e "${CYAN}▶ $1${NC}"; }

# ─── Input helpers ────────────────────────────────────────────────────────────

read_tty() {
    local prompt="$1"
    local default="${2:-}"
    local input=""

    printf "%s" "$prompt" >&2

    if [ -t 0 ]; then
        IFS= read -r input
    elif [ -r /dev/tty ]; then
        IFS= read -r input < /dev/tty
    fi

    if [ -z "$input" ] && [ -n "$default" ]; then
        input="$default"
    fi

    printf "%s" "$input"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn="[y/N]"
    [ "$default" = "y" ] && yn="[Y/n]"

    local input
    input=$(read_tty "$prompt $yn " "")
    [ -z "$input" ] && input="$default"

    [[ "$input" =~ ^[Yy]$ ]]
}

# ─── Path detection ───────────────────────────────────────────────────────────

# Script lives at: <workspace>/kit/skills/multiagency-discord-setup/scripts/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_WORKSPACE="$(dirname "$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")")"

if [ -z "${WORKSPACE_DIR:-}" ]; then
    if [ -d "$AUTO_WORKSPACE/kit" ]; then
        WORKSPACE_DIR="$AUTO_WORKSPACE"
    else
        WORKSPACE_DIR="$HOME/workspaces"
    fi
fi

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
KIT_DIR="${KIT_DIR:-$WORKSPACE_DIR/kit}"
AGENT_ID=""

# ─── Args ─────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent) AGENT_ID="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--agent <agent-id>]"
            echo
            echo "  --agent    Agent ID to configure Discord for"
            echo
            echo "If --agent is omitted, the script will prompt for selection."
            echo
            echo "Environment:"
            echo "  WORKSPACE_DIR  path to workspace root (default: auto-detect or ~/workspaces)"
            echo "  OPENCLAW_DIR   path to OpenClaw config dir (default: ~/.openclaw)"
            exit 0
            ;;
        *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
done

# ─── Validate config ─────────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "openclaw.json not found at $CONFIG_FILE"
    log_info "Set OPENCLAW_DIR if your config lives elsewhere."
    exit 1
fi

# ─── Banner ───────────────────────────────────────────────────────────────────

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Discord Agent Setup                                   ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

if [ -d "$KIT_DIR/workspace-template" ]; then
    log_info "Multi-agent workspace: $WORKSPACE_DIR"
else
    log_warn "workspace-template not found — workspace creation will be skipped"
fi

# ─── Step 1: Select or specify agent ─────────────────────────────────────────

log_step "Agent"

AGENTS_JSON=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    for a in config.get("agents", {}).get("list", []):
        print(a.get("id", ""))
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
) || { log_error "Failed to read agents from config"; exit 1; }

AGENT_EXISTS_IN_CONFIG=false

if [ -n "$AGENTS_JSON" ]; then
    log_info "Agents in config:"
    while IFS= read -r aid; do
        [ -n "$aid" ] && echo "  - $aid"
    done <<< "$AGENTS_JSON"
fi

if [ -z "$AGENT_ID" ]; then
    AGENT_ID=$(read_tty "Agent ID (existing or new): " "")
fi

if [ -z "$AGENT_ID" ]; then
    log_error "Agent ID is required"
    exit 1
fi

if [[ ! "$AGENT_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_error "Agent ID must be alphanumeric (hyphens/underscores OK)"
    exit 1
fi

if [ -n "$AGENTS_JSON" ] && echo "$AGENTS_JSON" | grep -qx "$AGENT_ID"; then
    AGENT_EXISTS_IN_CONFIG=true
    log_success "Agent '$AGENT_ID' found in config"
else
    log_info "Agent '$AGENT_ID' is new — will be added to config"
fi

# ─── Step 2: Discord bot setup guidance ───────────────────────────────────────

log_step "Create Discord Bot"

echo
log_info "If you haven't created a Discord bot yet:"
log_info "  1. Go to https://discord.com/developers/applications"
log_info "  2. Click 'New Application' → name it → click 'Bot' on sidebar"
log_info "  3. Enable: Message Content Intent + Server Members Intent"
log_info "  4. Click 'Reset Token' to get your bot token"
log_info "  5. Under OAuth2 → URL Generator: scopes 'bot' + 'applications.commands'"
log_info "     Permissions: View Channels, Send Messages, Read Message History,"
log_info "                  Embed Links, Attach Files"
log_info "  6. Open the generated URL to add the bot to your server"
log_info "  7. Enable Developer Mode: User Settings → Advanced → Developer Mode"
log_info "  8. Right-click server icon → Copy Server ID"
log_info "  9. Right-click your avatar → Copy User ID"
echo

BOT_TOKEN=$(read_tty "Bot token: " "")

if [ -z "$BOT_TOKEN" ]; then
    log_error "Bot token is required"
    exit 1
fi

if [ ${#BOT_TOKEN} -lt 50 ]; then
    log_warn "Token looks short (Discord tokens are typically 70+ characters)"
    if ! confirm "Continue anyway?" "n"; then
        exit 1
    fi
fi

log_success "Bot token received"

# ─── Step 3: Channel configuration ───────────────────────────────────────────

log_step "Discord Channel Configuration"

DEFAULT_ACCOUNT="$AGENT_ID"
ACCOUNT_ID=$(read_tty "Account ID [$DEFAULT_ACCOUNT]: " "$DEFAULT_ACCOUNT")

echo
SERVER_ID=$(read_tty "Discord Server (Guild) ID: " "")

if [ -z "$SERVER_ID" ]; then
    log_error "Server ID is required"
    exit 1
fi

if [[ ! "$SERVER_ID" =~ ^[0-9]+$ ]]; then
    log_warn "Server ID should be numeric (e.g., 123456789012345678)"
    if ! confirm "Continue anyway?" "n"; then
        exit 1
    fi
fi

EXISTING_USER_IDS=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    ids = set()
    for acct in config.get("channels", {}).get("discord", {}).get("accounts", {}).values():
        for guild in acct.get("guilds", {}).values():
            for uid in guild.get("users", []):
                if isinstance(uid, str) and uid.isdigit():
                    ids.add(uid)
    print(",".join(sorted(ids)))
except Exception:
    pass
PYEOF
)

echo
log_info "Your Discord user ID restricts who can trigger the bot."
if [ -n "$EXISTING_USER_IDS" ]; then
    log_info "Found existing user IDs in config: $EXISTING_USER_IDS"
else
    log_info "To find your Discord user ID: right-click your avatar → Copy User ID"
    log_info "(requires Developer Mode: User Settings → Advanced → Developer Mode)"
fi

USER_ID=$(read_tty "Discord User ID${EXISTING_USER_IDS:+ [$EXISTING_USER_IDS]}: " "$EXISTING_USER_IDS")

echo
log_info "Require @mention to respond in channels?"
log_info "  true  — bot only responds when @mentioned (recommended for shared servers)"
log_info "  false — bot responds to every message (good for private servers)"
REQUIRE_MENTION_INPUT=$(read_tty "Require mention [true]: " "true")
REQUIRE_MENTION="true"
[[ "$REQUIRE_MENTION_INPUT" =~ ^[Ff]alse$|^[Nn]o?$ ]] && REQUIRE_MENTION="false"

echo
DEFAULT_ENV_VAR="DISCORD_BOT_TOKEN"
log_info "The bot token will be stored as an env var reference in config."
TOKEN_ENV_VAR=$(read_tty "Env var name [$DEFAULT_ENV_VAR]: " "$DEFAULT_ENV_VAR")

# ─── Step 4: Preview ─────────────────────────────────────────────────────────

log_step "Configuration Preview"

WORKSPACE_PATH="$WORKSPACE_DIR/$AGENT_ID"

echo
if ! $AGENT_EXISTS_IN_CONFIG; then
    log_info "Will add to agents.list:"
    echo "  { id: \"$AGENT_ID\", workspace: \"$WORKSPACE_PATH\" }"
    echo
fi
log_info "Will set channels.discord.enabled: true"
echo
log_info "Will add to channels.discord.accounts:"
echo "  \"$ACCOUNT_ID\": {"
echo "    enabled: true"
echo "    token: { source: \"env\", provider: \"default\", id: \"$TOKEN_ENV_VAR\" }"
echo "    guilds: {"
echo "      \"$SERVER_ID\": {"
echo "        requireMention: $REQUIRE_MENTION"
[ -n "$USER_ID" ] && echo "        users: [\"$USER_ID\"]"
echo "      }"
echo "    }"
echo "  }"
echo
log_info "Will add to bindings:"
echo "  { agentId: \"$AGENT_ID\", match: { channel: \"discord\", accountId: \"$ACCOUNT_ID\" } }"
echo

if ! confirm "Write this to openclaw.json?" "y"; then
    log_info "Aborted"
    exit 0
fi

# ─── Step 5: Write config ────────────────────────────────────────────────────

log_step "Updating openclaw.json"

python3 - "$CONFIG_FILE" "$AGENT_ID" "$WORKSPACE_PATH" "$ACCOUNT_ID" "$BOT_TOKEN" "$SERVER_ID" "$USER_ID" "$REQUIRE_MENTION" "$TOKEN_ENV_VAR" "$AGENT_EXISTS_IN_CONFIG" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
agent_id = sys.argv[2]
workspace = sys.argv[3]
account_id = sys.argv[4]
bot_token = sys.argv[5]
server_id = sys.argv[6]
user_id = sys.argv[7] if len(sys.argv) > 7 else ""
require_mention = sys.argv[8] == "true" if len(sys.argv) > 8 else True
token_env_var = sys.argv[9] if len(sys.argv) > 9 else "DISCORD_BOT_TOKEN"
agent_exists = sys.argv[10] == "true" if len(sys.argv) > 10 else False

try:
    with open(config_file) as f:
        config = json.load(f)

    # Add agent if new
    if not agent_exists:
        agents = config.setdefault("agents", {}).setdefault("list", [])
        if not any(a.get("id") == agent_id for a in agents):
            agents.append({"id": agent_id, "workspace": workspace})
            print(f"Added agent '{agent_id}' to agents.list")
        else:
            print(f"Agent '{agent_id}' already in agents.list")
    else:
        print(f"Agent '{agent_id}' already in config")

    # Set up channels.discord
    discord = config.setdefault("channels", {}).setdefault("discord", {})
    discord["enabled"] = True
    accounts = discord.setdefault("accounts", {})

    if account_id in accounts:
        print(f"Warning: account '{account_id}' already exists — overwriting")

    # Build guild config
    guild_config = {"requireMention": require_mention}
    if user_id.strip():
        users = []
        for s in user_id.split(","):
            s = s.strip()
            if s:
                users.append(s)
        if users:
            guild_config["users"] = users

    acct = {
        "enabled": True,
        "token": {
            "source": "env",
            "provider": "default",
            "id": token_env_var
        },
        "guilds": {
            server_id: guild_config
        }
    }

    accounts[account_id] = acct
    print(f"Added Discord account '{account_id}'")

    # Add binding
    bindings = config.setdefault("bindings", [])
    binding_exists = any(
        b.get("agentId") == agent_id and
        b.get("match", {}).get("channel") == "discord" and
        b.get("match", {}).get("accountId") == account_id
        for b in bindings
    )
    if not binding_exists:
        bindings.append({
            "agentId": agent_id,
            "match": {
                "channel": "discord",
                "accountId": account_id
            }
        })
        print(f"Added binding: {agent_id} <-> {account_id}")
    else:
        print(f"Binding already exists for {agent_id} <-> {account_id}")

    # Ensure session idle timeout is configured
    sessions = config.setdefault("sessions", {})
    if "idleTimeout" not in sessions:
        sessions["idleTimeout"] = "7d"
        print("Set sessions.idleTimeout to '7d' (default)")

    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

log_success "openclaw.json updated"

# ─── Step 6: Create workspace ────────────────────────────────────────────────

if [ -d "$WORKSPACE_PATH" ]; then
    log_info "Workspace already exists: $WORKSPACE_PATH"
elif [ -d "$KIT_DIR/workspace-template" ]; then
    log_step "Create Agent Workspace"

    if confirm "Create workspace from template at $WORKSPACE_PATH?" "y"; then
        cp -r "$KIT_DIR/workspace-template" "$WORKSPACE_PATH"
        log_success "Workspace created: $WORKSPACE_PATH"
        echo
        log_info "Customize your agent:"
        log_info "  Edit $WORKSPACE_PATH/IDENTITY.md"
        log_info "  Edit $WORKSPACE_PATH/USER.md"
    else
        log_warn "Create workspace manually before starting the agent"
    fi
else
    log_warn "No workspace-template found — create agent workspace manually"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Discord Setup Complete                                ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║                                                        ║"
echo "║  Next steps:                                           ║"
echo "║    1. Export token: export $TOKEN_ENV_VAR=\"...\"         "
echo "║    2. Restart: openclaw gateway restart                ║"
echo "║    3. Message your bot on Discord                      ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo
