#!/bin/bash
#
# setup-telegram-agent.sh: Set up Telegram bot routing for an OpenClaw agent
#
# Usage: ./setup-telegram-agent.sh [--agent <agent-id>]
#
# Walks through:
#   1. Selecting or creating an agent
#   2. Creating a Telegram bot via BotFather
#   3. Configuring the Telegram account and binding in openclaw.json
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

# Script lives at: <workspace>/kit/skills/multiagency-telegram-setup/scripts/
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
            echo "  --agent    Agent ID to configure Telegram for"
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
echo "║  Telegram Agent Setup                                  ║"
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

# ─── Step 2: Telegram bot token ──────────────────────────────────────────────

log_step "Create Telegram Bot"

echo
log_info "1. Open Telegram and search for @BotFather"
log_info "2. Send /newbot"
log_info "3. Choose a name and username (must end in 'bot')"
log_info "4. BotFather will give you a token like: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
echo

BOT_TOKEN=$(read_tty "Bot token: " "")

if [ -z "$BOT_TOKEN" ]; then
    log_error "Bot token is required"
    exit 1
fi

if [[ ! "$BOT_TOKEN" =~ : ]] || [ ${#BOT_TOKEN} -lt 20 ]; then
    log_warn "Token looks invalid (expected format: 123456789:ABCdef...)"
    if ! confirm "Continue anyway?" "n"; then
        exit 1
    fi
fi

log_success "Bot token received"

# ─── Step 3: Channel configuration ───────────────────────────────────────────

log_step "Telegram Channel Configuration"

DEFAULT_ACCOUNT="${AGENT_ID}_bot"
ACCOUNT_ID=$(read_tty "Account ID [$DEFAULT_ACCOUNT]: " "$DEFAULT_ACCOUNT")

EXISTING_SENDER_IDS=$(python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    ids = set()
    for acct in config.get("channels", {}).get("telegram", {}).get("accounts", {}).values():
        for uid in acct.get("allowFrom", []):
            if isinstance(uid, int) and uid > 0:
                ids.add(uid)
    print(",".join(str(i) for i in sorted(ids)))
except Exception:
    pass
PYEOF
)

echo
log_info "Who should be allowed to message this bot?"
if [ -n "$EXISTING_SENDER_IDS" ]; then
    log_info "Found existing sender IDs in config: $EXISTING_SENDER_IDS"
else
    log_info "To find your Telegram user ID, message @userinfobot on Telegram."
fi

ALLOW_FROM=$(read_tty "Allowed sender IDs (comma-separated)${EXISTING_SENDER_IDS:+ [$EXISTING_SENDER_IDS]}: " "$EXISTING_SENDER_IDS")

if [ -z "$ALLOW_FROM" ]; then
    log_warn "No sender IDs — the bot will not accept DMs from anyone."
    if ! confirm "Continue without sender IDs?" "n"; then
        exit 1
    fi
fi

echo
log_info "DM policy:"
log_info "  pairing   — route based on bindings (recommended)"
log_info "  allowlist — only allowFrom users can DM"
DM_POLICY=$(read_tty "DM policy [pairing]: " "pairing")

# ─── Step 4: Preview ─────────────────────────────────────────────────────────

log_step "Configuration Preview"

WORKSPACE_PATH="$WORKSPACE_DIR/$AGENT_ID"

echo
if ! $AGENT_EXISTS_IN_CONFIG; then
    log_info "Will add to agents.list:"
    echo "  { id: \"$AGENT_ID\", workspace: \"$WORKSPACE_PATH\" }"
    echo
fi
log_info "Will add to channels.telegram.accounts:"
echo "  \"$ACCOUNT_ID\": {"
echo "    enabled: true"
echo "    dmPolicy: \"$DM_POLICY\""
echo "    botToken: \"${BOT_TOKEN:0:10}...\""
[ -n "$ALLOW_FROM" ] && echo "    allowFrom: [$ALLOW_FROM]"
echo "    groupPolicy: \"allowlist\""
echo "    streaming: \"partial\""
echo "  }"
echo
log_info "Will add to bindings:"
echo "  { agentId: \"$AGENT_ID\", match: { channel: \"telegram\", accountId: \"$ACCOUNT_ID\" } }"
echo

if ! confirm "Write this to openclaw.json?" "y"; then
    log_info "Aborted"
    exit 0
fi

# ─── Step 5: Write config ────────────────────────────────────────────────────

log_step "Updating openclaw.json"

python3 - "$CONFIG_FILE" "$AGENT_ID" "$WORKSPACE_PATH" "$ACCOUNT_ID" "$BOT_TOKEN" "$ALLOW_FROM" "$DM_POLICY" "$AGENT_EXISTS_IN_CONFIG" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
agent_id = sys.argv[2]
workspace = sys.argv[3]
account_id = sys.argv[4]
bot_token = sys.argv[5]
allow_from_str = sys.argv[6] if len(sys.argv) > 6 else ""
dm_policy = sys.argv[7] if len(sys.argv) > 7 else "pairing"
agent_exists = sys.argv[8] == "true" if len(sys.argv) > 8 else False

try:
    with open(config_file) as f:
        config = json.load(f)

    if not agent_exists:
        agents = config.setdefault("agents", {}).setdefault("list", [])
        if not any(a.get("id") == agent_id for a in agents):
            agents.append({"id": agent_id, "workspace": workspace})
            print(f"Added agent '{agent_id}' to agents.list")
        else:
            print(f"Agent '{agent_id}' already in agents.list")
    else:
        print(f"Agent '{agent_id}' already in config")

    telegram = config.setdefault("channels", {}).setdefault("telegram", {})
    accounts = telegram.setdefault("accounts", {})

    if account_id in accounts:
        print(f"Warning: account '{account_id}' already exists — overwriting")

    acct = {
        "enabled": True,
        "dmPolicy": dm_policy,
        "botToken": bot_token,
        "groupPolicy": "allowlist",
        "streaming": "partial"
    }

    if allow_from_str.strip():
        allow_from = []
        for s in allow_from_str.split(","):
            s = s.strip()
            if s:
                try:
                    allow_from.append(int(s))
                except ValueError:
                    print(f"Warning: skipping non-numeric sender ID: {s}", file=sys.stderr)
        if allow_from:
            acct["allowFrom"] = allow_from

    accounts[account_id] = acct
    print(f"Added Telegram account '{account_id}'")

    bindings = config.setdefault("bindings", [])
    binding_exists = any(
        b.get("agentId") == agent_id and
        b.get("match", {}).get("channel") == "telegram" and
        b.get("match", {}).get("accountId") == account_id
        for b in bindings
    )
    if not binding_exists:
        bindings.append({
            "agentId": agent_id,
            "match": {
                "channel": "telegram",
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
echo "║  Telegram Setup Complete                               ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║                                                        ║"
echo "║  Next steps:                                           ║"
echo "║    1. Message your bot on Telegram: /start             ║"
echo "║    2. Restart: openclaw gateway restart                ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo
