#!/bin/bash
#
# setup-telegram-group.sh: Configure a dedicated Telegram group for an existing agent
#
# Usage: ./setup-telegram-group.sh [--agent <agent-id>] [--account <account-id>] [--group <chat-id>]
#
# Writes group config directly into openclaw.json under the agent's Telegram account.
# Designed for dedicated (single-agent) groups where requireMention is false.

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
GROUP_CHAT_ID=""

# ─── Args ─────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)   AGENT_ID="$2";      shift 2 ;;
        --account) ACCOUNT_ID="$2";    shift 2 ;;
        --group)   GROUP_CHAT_ID="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--agent <agent-id>] [--account <account-id>] [--group <chat-id>]"
            echo
            echo "  --agent    Agent ID (must exist in openclaw.json agents.list)"
            echo "  --account  Telegram account ID under channels.telegram.accounts"
            echo "  --group    Telegram group chat ID (negative number, e.g. -1001234567890)"
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

# ─── Step 2: Select Telegram account ─────────────────────────────────────────

log_step "Select Telegram Account"

ACCOUNT_INFO=$(python3 - "$CONFIG_FILE" "$AGENT_ID" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
agent_id = sys.argv[2]

try:
    with open(config_file) as f:
        config = json.load(f)

    accounts = list(config.get("channels", {}).get("telegram", {}).get("accounts", {}).keys())
    bindings = config.get("bindings", [])

    bound = [
        b.get("match", {}).get("accountId")
        for b in bindings
        if b.get("agentId") == agent_id and b.get("match", {}).get("channel") == "telegram"
    ]
    bound = [a for a in bound if a]

    print(f"ACCOUNTS:{','.join(accounts)}")
    print(f"BOUND:{','.join(bound)}")
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
) || { log_error "Failed to read Telegram accounts from config"; exit 1; }

ALL_ACCOUNTS=$(echo "$ACCOUNT_INFO" | grep "^ACCOUNTS:" | sed 's/^ACCOUNTS://')
BOUND_ACCOUNTS=$(echo "$ACCOUNT_INFO" | grep "^BOUND:" | sed 's/^BOUND://')

if [ -z "$ALL_ACCOUNTS" ]; then
    log_error "No Telegram accounts found in channels.telegram.accounts"
    log_info "Set up a Telegram bot first with setup-telegram-agent.sh"
    exit 1
fi

BOUND_COUNT=$(echo "$BOUND_ACCOUNTS" | tr ',' '\n' | grep -c . || true)

if [ -z "$ACCOUNT_ID" ]; then
    if [ "$BOUND_COUNT" -eq 1 ]; then
        ACCOUNT_ID="$BOUND_ACCOUNTS"
        log_info "Auto-detected account bound to $AGENT_ID: $ACCOUNT_ID"
    else
        log_info "Telegram accounts: $ALL_ACCOUNTS"
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
    log_error "Account '$ACCOUNT_ID' not found in channels.telegram.accounts"
    exit 1
fi

log_success "Account: $ACCOUNT_ID"

# ─── Step 3: Group chat ID ───────────────────────────────────────────────────

log_step "Telegram Group Chat ID"

echo
log_info "To find your group's chat ID:"
log_info "  1. Add the bot to your Telegram group"
log_info "  2. Send a message in the group"
log_info "  3. Check gateway logs: openclaw logs --follow"
log_info "  4. Look for 'chatId' in the routing output (negative number)"
log_info "  Or forward a group message to @userinfobot on Telegram"
echo

if [ -z "$GROUP_CHAT_ID" ]; then
    GROUP_CHAT_ID=$(read_tty "Group chat ID (e.g. -1001234567890): " "")
fi

if [ -z "$GROUP_CHAT_ID" ]; then
    log_error "Group chat ID is required"
    exit 1
fi

if [[ ! "$GROUP_CHAT_ID" =~ ^-[0-9]+$ ]]; then
    log_warn "Chat ID '$GROUP_CHAT_ID' doesn't look like a Telegram group ID (expected negative number)"
    if ! confirm "Continue anyway?" "n"; then
        exit 1
    fi
fi

log_success "Group: $GROUP_CHAT_ID"

# ─── Step 4: Sender allowlist ─────────────────────────────────────────────────

log_step "Group Sender Allowlist"

EXISTING_ALLOW_FROM=$(python3 - "$CONFIG_FILE" "$ACCOUNT_ID" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    acct = config.get("channels", {}).get("telegram", {}).get("accounts", {}).get(sys.argv[2], {})
    ids = acct.get("allowFrom", [])
    print(",".join(str(i) for i in ids if isinstance(i, int) and i > 0))
except Exception:
    pass
PYEOF
)

echo
log_info "Which Telegram user IDs should be allowed to talk to the bot in this group?"
log_info "This sets groupAllowFrom on the account (controls who can trigger the bot)."
if [ -n "$EXISTING_ALLOW_FROM" ]; then
    log_info "Found existing allowFrom on account: $EXISTING_ALLOW_FROM"
fi
log_info "To find your ID: message @userinfobot on Telegram, or check gateway logs."
echo

SENDER_IDS=$(read_tty "Allowed sender IDs (comma-separated)${EXISTING_ALLOW_FROM:+ [$EXISTING_ALLOW_FROM]}: " "$EXISTING_ALLOW_FROM")

if [ -z "$SENDER_IDS" ]; then
    log_warn "No sender IDs provided — only existing allowFrom/groupAllowFrom will apply."
fi

# ─── Step 5: Preview and confirm ─────────────────────────────────────────────

log_step "Configuration Preview"

echo
log_info "Will add to channels.telegram.groups:"
echo "  \"$GROUP_CHAT_ID\": {"
echo "    enabled: true"
echo "    requireMention: false"
echo "    groupPolicy: \"open\""
echo "  }"
echo
log_info "Will update channels.telegram.accounts.$ACCOUNT_ID:"
echo "  groupPolicy: \"allowlist\""
if [ -n "$SENDER_IDS" ]; then
    echo "  allowFrom: [$SENDER_IDS]"
    echo "  groupAllowFrom: [$SENDER_IDS]"
fi
echo

if ! confirm "Write this to openclaw.json?" "y"; then
    log_info "Aborted"
    exit 0
fi

# ─── Step 6: Write config ────────────────────────────────────────────────────

log_step "Updating openclaw.json"

python3 - "$CONFIG_FILE" "$ACCOUNT_ID" "$GROUP_CHAT_ID" "$SENDER_IDS" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
account_id = sys.argv[2]
group_chat_id = sys.argv[3]
sender_ids_str = sys.argv[4] if len(sys.argv) > 4 else ""

try:
    with open(config_file) as f:
        config = json.load(f)

    telegram = config.setdefault("channels", {}).setdefault("telegram", {})

    # Add group to channels.telegram.groups
    groups = telegram.setdefault("groups", {})
    if group_chat_id not in groups:
        groups[group_chat_id] = {}
    groups[group_chat_id]["enabled"] = True
    groups[group_chat_id]["requireMention"] = False
    groups[group_chat_id]["groupPolicy"] = "open"
    print(f"Added group {group_chat_id} to channels.telegram.groups")

    # Update account: groupPolicy, allowFrom, groupAllowFrom
    accounts = telegram.get("accounts", {})
    if account_id not in accounts:
        print(f"Account '{account_id}' not found", file=sys.stderr)
        sys.exit(1)

    acct = accounts[account_id]
    acct["groupPolicy"] = "allowlist"

    if sender_ids_str.strip():
        sender_ids = []
        for s in sender_ids_str.split(","):
            s = s.strip()
            if s:
                try:
                    sender_ids.append(int(s))
                except ValueError:
                    print(f"Warning: skipping non-numeric sender ID: {s}", file=sys.stderr)

        if sender_ids:
            existing_allow = set(acct.get("allowFrom", []))
            existing_allow.update(sender_ids)
            acct["allowFrom"] = sorted(existing_allow)

            existing_group_allow = set(acct.get("groupAllowFrom", []))
            existing_group_allow.update(sender_ids)
            acct["groupAllowFrom"] = sorted(existing_group_allow)

            print(f"Updated allowFrom and groupAllowFrom on account '{account_id}'")

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
log_info "1. Make sure the bot is added to the Telegram group"
log_info "2. Promote the bot to admin (needed to see all group messages)"
log_info "3. If the bot still misses messages, disable privacy mode:"
log_info "     Open @BotFather → /setprivacy → select bot → Disable"
log_info "     Then remove and re-add the bot to the group"
echo
log_warn "Restart the gateway to apply: openclaw gateway restart"
echo
