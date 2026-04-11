#!/bin/bash
#
# setup-discord-guild.sh: Add a Discord server (guild) to an existing agent's Discord account
#
# Usage: ./setup-discord-guild.sh [--agent <agent-id>] [--account <account-id>] [--guild <server-id>]
#
# Writes guild config directly into openclaw.json under the agent's Discord account.

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

# ─── Defaults ─────────────────────────────────────────────────────────────────

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
AGENT_ID=""
ACCOUNT_ID=""
GUILD_ID=""

# ─── Args ─────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)   AGENT_ID="$2";   shift 2 ;;
        --account) ACCOUNT_ID="$2"; shift 2 ;;
        --guild)   GUILD_ID="$2";   shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--agent <agent-id>] [--account <account-id>] [--guild <server-id>]"
            echo
            echo "  --agent    Agent ID (must exist in openclaw.json agents.list)"
            echo "  --account  Discord account ID under channels.discord.accounts"
            echo "  --guild    Discord server (guild) ID"
            echo
            echo "All arguments are optional — the script will prompt for missing values."
            echo
            echo "Environment:"
            echo "  OPENCLAW_DIR  path to OpenClaw config dir (default: ~/.openclaw)"
            exit 0
            ;;
        *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
done

# ─── Validate config exists ──────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "openclaw.json not found at $CONFIG_FILE"
    log_info "Set OPENCLAW_DIR if your config lives elsewhere."
    exit 1
fi

# ─── Banner ───────────────────────────────────────────────────────────────────

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Discord Guild Setup                                   ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

# ─── Step 1: Select agent ────────────────────────────────────────────────────

log_step "Select Agent"

AGENTS_JSON=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    agents = config.get("agents", {}).get("list", [])
    for a in agents:
        print(a.get("id", ""))
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
) || { log_error "Failed to read agents from config"; exit 1; }

if [ -z "$AGENTS_JSON" ]; then
    log_error "No agents found in openclaw.json"
    exit 1
fi

log_info "Available agents:"
while IFS= read -r aid; do
    [ -n "$aid" ] && echo "  - $aid"
done <<< "$AGENTS_JSON"

if [ -z "$AGENT_ID" ]; then
    AGENT_ID=$(read_tty "Agent ID: " "")
fi

if [ -z "$AGENT_ID" ]; then
    log_error "Agent ID is required"
    exit 1
fi

if ! echo "$AGENTS_JSON" | grep -qx "$AGENT_ID"; then
    log_error "Agent '$AGENT_ID' not found in openclaw.json agents.list"
    exit 1
fi

log_success "Agent: $AGENT_ID"

# ─── Step 2: Select Discord account ──────────────────────────────────────────

log_step "Select Discord Account"

ACCOUNT_INFO=$(python3 - "$CONFIG_FILE" "$AGENT_ID" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
agent_id = sys.argv[2]

try:
    with open(config_file) as f:
        config = json.load(f)

    accounts = list(config.get("channels", {}).get("discord", {}).get("accounts", {}).keys())
    bindings = config.get("bindings", [])

    bound = [
        b.get("match", {}).get("accountId")
        for b in bindings
        if b.get("agentId") == agent_id and b.get("match", {}).get("channel") == "discord"
    ]
    bound = [a for a in bound if a]

    print(f"ACCOUNTS:{','.join(accounts)}")
    print(f"BOUND:{','.join(bound)}")
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
) || { log_error "Failed to read Discord accounts from config"; exit 1; }

ALL_ACCOUNTS=$(echo "$ACCOUNT_INFO" | grep "^ACCOUNTS:" | sed 's/^ACCOUNTS://')
BOUND_ACCOUNTS=$(echo "$ACCOUNT_INFO" | grep "^BOUND:" | sed 's/^BOUND://')

if [ -z "$ALL_ACCOUNTS" ]; then
    log_error "No Discord accounts found in channels.discord.accounts"
    log_info "Set up a Discord bot first with setup-discord-agent.sh"
    exit 1
fi

BOUND_COUNT=$(echo "$BOUND_ACCOUNTS" | tr ',' '\n' | grep -c . || true)

if [ -z "$ACCOUNT_ID" ]; then
    if [ "$BOUND_COUNT" -eq 1 ]; then
        ACCOUNT_ID="$BOUND_ACCOUNTS"
        log_info "Auto-detected account bound to $AGENT_ID: $ACCOUNT_ID"
    else
        log_info "Discord accounts: $ALL_ACCOUNTS"
        if [ "$BOUND_COUNT" -gt 0 ]; then
            log_info "Accounts bound to $AGENT_ID: $BOUND_ACCOUNTS"
        fi
        ACCOUNT_ID=$(read_tty "Account ID: " "")
    fi
fi

if [ -z "$ACCOUNT_ID" ]; then
    log_error "Account ID is required"
    exit 1
fi

if ! echo "$ALL_ACCOUNTS" | tr ',' '\n' | grep -qx "$ACCOUNT_ID"; then
    log_error "Account '$ACCOUNT_ID' not found in channels.discord.accounts"
    exit 1
fi

log_success "Account: $ACCOUNT_ID"

# ─── Step 3: Guild (server) ID ───────────────────────────────────────────────

log_step "Discord Server (Guild) ID"

echo
log_info "To find your server ID:"
log_info "  1. Enable Developer Mode: User Settings → Advanced → Developer Mode"
log_info "  2. Right-click the server icon → Copy Server ID"
echo

if [ -z "$GUILD_ID" ]; then
    GUILD_ID=$(read_tty "Server (Guild) ID: " "")
fi

if [ -z "$GUILD_ID" ]; then
    log_error "Server ID is required"
    exit 1
fi

if [[ ! "$GUILD_ID" =~ ^[0-9]+$ ]]; then
    log_warn "Server ID '$GUILD_ID' doesn't look like a Discord server ID (expected numeric)"
    if ! confirm "Continue anyway?" "n"; then
        exit 1
    fi
fi

log_success "Guild: $GUILD_ID"

# ─── Step 4: Guild settings ──────────────────────────────────────────────────

log_step "Guild Settings"

echo
log_info "Require @mention to respond in channels?"
log_info "  true  — bot only responds when @mentioned (recommended for shared servers)"
log_info "  false — bot responds to every message (good for private servers)"
REQUIRE_MENTION_INPUT=$(read_tty "Require mention [true]: " "true")
REQUIRE_MENTION="true"
[[ "$REQUIRE_MENTION_INPUT" =~ ^[Ff]alse$|^[Nn]o?$ ]] && REQUIRE_MENTION="false"

EXISTING_USER_IDS=$(python3 - "$CONFIG_FILE" "$ACCOUNT_ID" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    acct = config.get("channels", {}).get("discord", {}).get("accounts", {}).get(sys.argv[2], {})
    ids = set()
    for guild in acct.get("guilds", {}).values():
        for uid in guild.get("users", []):
            if isinstance(uid, str) and uid.strip():
                ids.add(uid.strip())
    print(",".join(sorted(ids)))
except Exception:
    pass
PYEOF
)

echo
log_info "Which Discord user IDs should be allowed to trigger the bot in this server?"
if [ -n "$EXISTING_USER_IDS" ]; then
    log_info "Found existing user IDs on this account: $EXISTING_USER_IDS"
else
    log_info "To find your Discord user ID: right-click your avatar → Copy User ID"
fi

USER_IDS=$(read_tty "Allowed user IDs (comma-separated)${EXISTING_USER_IDS:+ [$EXISTING_USER_IDS]}: " "$EXISTING_USER_IDS")

# ─── Step 5: Preview and confirm ─────────────────────────────────────────────

log_step "Configuration Preview"

echo
log_info "Will add to channels.discord.accounts.$ACCOUNT_ID.guilds:"
echo "  \"$GUILD_ID\": {"
echo "    requireMention: $REQUIRE_MENTION"
[ -n "$USER_IDS" ] && echo "    users: [\"${USER_IDS//,/\", \"}\"]"
echo "  }"
echo

if ! confirm "Write this to openclaw.json?" "y"; then
    log_info "Aborted"
    exit 0
fi

# ─── Step 6: Write config ────────────────────────────────────────────────────

log_step "Updating openclaw.json"

python3 - "$CONFIG_FILE" "$ACCOUNT_ID" "$GUILD_ID" "$REQUIRE_MENTION" "$USER_IDS" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
account_id = sys.argv[2]
guild_id = sys.argv[3]
require_mention = sys.argv[4] == "true" if len(sys.argv) > 4 else True
user_ids_str = sys.argv[5] if len(sys.argv) > 5 else ""

try:
    with open(config_file) as f:
        config = json.load(f)

    discord = config.get("channels", {}).get("discord", {})
    accounts = discord.get("accounts", {})

    if account_id not in accounts:
        print(f"Account '{account_id}' not found in channels.discord.accounts", file=sys.stderr)
        sys.exit(1)

    acct = accounts[account_id]
    guilds = acct.setdefault("guilds", {})

    guild_config = guilds.get(guild_id, {})
    guild_config["requireMention"] = require_mention

    if user_ids_str.strip():
        users = []
        existing_users = set(guild_config.get("users", []))
        for s in user_ids_str.split(","):
            s = s.strip()
            if s:
                existing_users.add(s)
        guild_config["users"] = sorted(existing_users)

    guilds[guild_id] = guild_config
    print(f"Added guild {guild_id} to account '{account_id}'")

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

# ─── Post-setup instructions ─────────────────────────────────────────────────

echo
log_step "Next Steps"

echo
log_info "1. Make sure the bot has been added to the Discord server"
log_info "   (use the OAuth2 URL from the Developer Portal if not)"
log_info "2. The bot needs these permissions in the server:"
log_info "     View Channels, Send Messages, Read Message History"
echo
log_warn "Restart the gateway to apply: openclaw gateway restart"
echo
