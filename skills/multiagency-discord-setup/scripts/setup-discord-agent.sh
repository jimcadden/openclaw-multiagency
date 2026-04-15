#!/bin/bash
#
# setup-discord-agent.sh: Set up Discord bot routing for an OpenClaw agent
#
# Usage: ./setup-discord-agent.sh [--agent <agent-id>]
#
# Walks through:
#   1. Selecting or creating an agent
#   2. Creating a Discord bot via the Developer Portal
#   3. Storing the bot token via the active secrets provider (env/file/exec)
#   4. Configuring the Discord account and binding in openclaw.json
#   5. Optionally creating the agent workspace from template

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

# ─── Source helpers ───────────────────────────────────────────────────────────

SECRETS_HELPER="$KIT_DIR/scripts/lib/secrets-helper.sh"
if [ -f "$SECRETS_HELPER" ]; then
    source "$SECRETS_HELPER"
else
    log_warn "secrets-helper.sh not found at $SECRETS_HELPER"
    log_warn "Token will need to be stored manually."
fi

CONFIG_HELPER="$KIT_DIR/scripts/lib/config-helper.sh"
if [ -f "$CONFIG_HELPER" ]; then
    source "$CONFIG_HELPER"
fi

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

# ─── Detect secrets provider ─────────────────────────────────────────────────

SECRETS_PROVIDER="env"
if type detect_secrets_provider &>/dev/null; then
    SECRETS_PROVIDER=$(detect_secrets_provider)
    log_info "Secrets provider: $SECRETS_PROVIDER"
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

# Per-agent env var naming convention
AGENT_UPPER=$(echo "$AGENT_ID" | tr '[:lower:]-' '[:upper:]_')
DEFAULT_ENV_VAR="DISCORD_BOT_TOKEN_${AGENT_UPPER}"
echo
log_info "The bot token will be stored via the '$SECRETS_PROVIDER' secrets provider."
log_info "SecretRef ID (env var name for env provider):"
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

# ─── Step 5: Store token via secrets provider ─────────────────────────────────

log_step "Storing Bot Token"

TOKEN_STORED=true
if type persist_secret_value &>/dev/null; then
    if ! persist_secret_value "$SECRETS_PROVIDER" "$TOKEN_ENV_VAR" "$BOT_TOKEN"; then
        TOKEN_STORED=false
        log_warn "Token not auto-stored. You must store it manually before starting the gateway."
    fi
else
    log_warn "secrets-helper not loaded — store the token manually"
    TOKEN_STORED=false
fi

# ─── Step 6: Write config ────────────────────────────────────────────────────

log_step "Updating openclaw.json"

oc_config_set_json "channels.discord.enabled" "true"

# Write SecretRef for the bot token
if type write_secret_ref &>/dev/null; then
    write_secret_ref "channels.discord.accounts.${ACCOUNT_ID}.token" "default" "env" "$TOKEN_ENV_VAR" || true
fi

oc_config_set_json "channels.discord.accounts.${ACCOUNT_ID}.enabled" "true"

GUILD_BASE="channels.discord.accounts.${ACCOUNT_ID}.guilds.${SERVER_ID}"
oc_config_set_json "${GUILD_BASE}.requireMention" "$REQUIRE_MENTION"

if [ -n "$USER_ID" ]; then
    IFS=',' read -ra ID_ARRAY <<< "$USER_ID"
    for uid in "${ID_ARRAY[@]}"; do
        uid=$(echo "$uid" | xargs)
        [ -n "$uid" ] && oc_array_add_if_absent "${GUILD_BASE}.users" "$uid"
    done
fi

# Register agent if new
if ! $AGENT_EXISTS_IN_CONFIG; then
    oc_agents_add "$AGENT_ID" "$WORKSPACE_PATH"
fi

# Add binding
oc_agents_bind "$AGENT_ID" "discord:$ACCOUNT_ID"

# Set session idle timeout if not already configured
oc_config_set_if_missing "session.idleMinutes" "10080"

log_success "openclaw.json updated"

# ─── Step 7: Validate SecretRef ───────────────────────────────────────────────

if type validate_secret_ref &>/dev/null && $TOKEN_STORED; then
    log_step "Validating SecretRef"
    validate_secret_ref "channels.discord.accounts.${ACCOUNT_ID}.token" "default" "env" "$TOKEN_ENV_VAR" || true
fi

# ─── Step 8: Create workspace ────────────────────────────────────────────────

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
if $TOKEN_STORED; then
echo "║  Token stored via $SECRETS_PROVIDER provider.                       "
else
echo "║  ⚠  Token NOT stored — add it to your secrets backend ║"
echo "║     Env var name: $TOKEN_ENV_VAR"
fi
echo "║                                                        ║"
echo "║  Next steps:                                           ║"
echo "║    1. openclaw secrets audit --check                   ║"
echo "║    2. openclaw gateway restart                         ║"
echo "║    3. Message your bot on Discord                      ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo
