#!/bin/bash
#
# manage-discord.sh: View and manage Discord bot configuration
#
# Usage: ./manage-discord.sh <command> [options]
#
# Commands:
#   list                                List all Discord accounts, guilds, and channels
#   allowlist show   [--account ...]    Show user/role allowlist for a guild
#   allowlist add    [--account ...] --guild <id> [--user <id>] [--role <id>]
#   allowlist remove [--account ...] --guild <id> [--user <id>] [--role <id>]
#   guild add        [--account ...] --guild <id> [--require-mention true|false] [--users <ids>]
#   guild remove     [--account ...] --guild <id>
#   channel add      [--account ...] --guild <id> --channel <id> [--require-mention true|false]
#   channel remove   [--account ...] --guild <id> --channel <id>
#   channel list     [--account ...] --guild <id>
#   mention on       [--account ...] --guild <id> [--channel <id>]
#   mention off      [--account ...] --guild <id> [--channel <id>]

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }
log_step()    { echo; echo -e "${CYAN}▶ $1${NC}"; }

# ─── Defaults ─────────────────────────────────────────────────────────────────

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_WORKSPACE="$(dirname "$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")")"
KIT_DIR="${KIT_DIR:-$AUTO_WORKSPACE/kit}"
if [ ! -d "$KIT_DIR" ] && [ -d "$AUTO_WORKSPACE" ]; then
    KIT_DIR="$AUTO_WORKSPACE"
fi

CONFIG_HELPER="$KIT_DIR/scripts/lib/config-helper.sh"
if [ -f "$CONFIG_HELPER" ]; then
    source "$CONFIG_HELPER"
fi

# ─── Validate ─────────────────────────────────────────────────────────────────

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "openclaw.json not found at $CONFIG_FILE"
    log_info "Set OPENCLAW_DIR if your config lives elsewhere."
    exit 1
fi

# ─── Usage ────────────────────────────────────────────────────────────────────

show_help() {
    echo "Usage: manage-discord.sh <command> [options]"
    echo
    echo "Commands:"
    echo "  list                               List all Discord accounts, guilds, and channels"
    echo "  allowlist show   [opts]             Show user/role allowlist for a guild"
    echo "  allowlist add    [opts]             Add a user or role to a guild allowlist"
    echo "  allowlist remove [opts]             Remove a user or role from a guild allowlist"
    echo "  guild add        [opts]             Add a guild (server) to a Discord account"
    echo "  guild remove     [opts]             Remove a guild from a Discord account"
    echo "  channel add      [opts]             Add a channel to a guild's channel allowlist"
    echo "  channel remove   [opts]             Remove a channel from a guild"
    echo "  channel list     [opts]             List channels in a guild's allowlist"
    echo "  mention on       [opts]             Set requireMention: true"
    echo "  mention off      [opts]             Set requireMention: false"
    echo
    echo "Common options:"
    echo "  --account <id>   Discord account ID (auto-detected if only one exists)"
    echo "  --guild <id>     Discord server (guild) ID"
    echo "  --channel <id>   Discord channel ID"
    echo "  --user <id>      Discord user ID"
    echo "  --role <id>      Discord role ID"
    echo
    echo "Environment:"
    echo "  OPENCLAW_DIR     path to OpenClaw config dir (default: ~/.openclaw)"
}

# ─── Config reading helpers (Python) ──────────────────────────────────────────

get_discord_json() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    discord = config.get("channels", {}).get("discord", {})
    print(json.dumps(discord, indent=2))
except Exception as e:
    print("{}")
PYEOF
}

list_account_ids() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
    accounts = config.get("channels", {}).get("discord", {}).get("accounts", {})
    for aid in accounts:
        print(aid)
except Exception:
    pass
PYEOF
}

auto_detect_account() {
    local accounts
    accounts=$(list_account_ids)
    local count
    count=$(echo "$accounts" | grep -c . 2>/dev/null || echo 0)

    if [ "$count" -eq 0 ]; then
        log_error "No Discord accounts found in config"
        exit 1
    elif [ "$count" -eq 1 ]; then
        echo "$accounts"
    else
        log_error "Multiple Discord accounts found. Specify --account <id>:"
        echo "$accounts" | while read -r a; do echo "  - $a"; done
        exit 1
    fi
}

# ─── Config modification helpers (delegate to config-helper.sh) ───────────────

config_set() {
    local path="$1"
    local value="$2"
    local strict="${3:-}"

    if [ "$strict" = "--strict-json" ]; then
        oc_config_set_json "$path" "$value"
    else
        oc_config_set "$path" "$value"
    fi
}

config_unset() {
    oc_config_unset "$1"
}

array_add() {
    oc_array_add_if_absent "$1" "$2"
}

array_remove() {
    local path="$1"
    local value="$2"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    python3 - "$config_file" "$path" "$value" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
path = sys.argv[2]
value = sys.argv[3]

try:
    with open(config_file) as f:
        config = json.load(f)
    parts = path.split(".")
    obj = config
    for part in parts[:-1]:
        if part not in obj:
            print(f"Path not found: {path}")
            sys.exit(0)
        obj = obj[part]
    arr = obj.get(parts[-1], [])
    if value in arr:
        arr.remove(value)
        obj[parts[-1]] = arr
        with open(config_file, "w") as f:
            json.dump(config, f, indent=2)
        print(f"Removed {value} from {path}")
    else:
        print(f"{value} not found in {path}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# Commands
# ═══════════════════════════════════════════════════════════════════════════════

# ─── list ─────────────────────────────────────────────────────────────────────

cmd_list() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys

try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
except Exception as e:
    print(f"Error reading config: {e}", file=sys.stderr)
    sys.exit(1)

discord = config.get("channels", {}).get("discord", {})
accounts = discord.get("accounts", {})
bindings = config.get("bindings", [])

enabled = discord.get("enabled", False)
group_policy = discord.get("groupPolicy", "allowlist")

print(f"Discord: {'enabled' if enabled else 'disabled'}  (groupPolicy: {group_policy})")
print()

if not accounts:
    print("  No accounts configured.")
    sys.exit(0)

for acct_id, acct in accounts.items():
    acct_enabled = acct.get("enabled", True)
    status = "enabled" if acct_enabled else "disabled"

    # Token display: show ref type, never the value
    token = acct.get("token", {})
    if isinstance(token, dict):
        token_display = f"{token.get('source','?')}:{token.get('provider','?')}:{token.get('id','?')}"
    elif isinstance(token, str):
        token_display = "PLAINTEXT (migrate with openclaw secrets configure)"
    else:
        token_display = "not configured"

    # Find bound agent
    bound_agents = [
        b.get("agentId") for b in bindings
        if b.get("match", {}).get("channel") == "discord"
        and b.get("match", {}).get("accountId") == acct_id
    ]

    print(f"  {acct_id} ({status})")
    print(f"    Token: {token_display}")
    if bound_agents:
        print(f"    Bound to: {', '.join(bound_agents)}")

    guilds = acct.get("guilds", {})
    if not guilds:
        print("    Guilds: (none)")
    else:
        print("    Guilds:")
        for guild_id, guild_cfg in guilds.items():
            mention = guild_cfg.get("requireMention", True)
            users = guild_cfg.get("users", [])
            roles = guild_cfg.get("roles", [])
            channels = guild_cfg.get("channels", {})
            ignore_other = guild_cfg.get("ignoreOtherMentions", False)

            print(f"      {guild_id}")
            print(f"        requireMention: {str(mention).lower()}")
            if ignore_other:
                print(f"        ignoreOtherMentions: true")
            if users:
                print(f"        users: {users}")
            if roles:
                print(f"        roles: {roles}")
            if channels:
                print(f"        channels:")
                for ch_id, ch_cfg in channels.items():
                    allow = ch_cfg.get("allow", True)
                    ch_mention = ch_cfg.get("requireMention", None)
                    parts = [f"allow: {str(allow).lower()}"]
                    if ch_mention is not None:
                        parts.append(f"requireMention: {str(ch_mention).lower()}")
                    print(f"          {ch_id} ({', '.join(parts)})")
            else:
                print(f"        channels: (all allowed)")
    print()
PYEOF
}

# ─── allowlist ────────────────────────────────────────────────────────────────

cmd_allowlist() {
    local subcmd="${1:-show}"
    shift || true

    local account="" guild="" user="" role=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account) account="$2"; shift 2 ;;
            --guild)   guild="$2";   shift 2 ;;
            --user)    user="$2";    shift 2 ;;
            --role)    role="$2";    shift 2 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    [ -z "$account" ] && account=$(auto_detect_account)

    case "$subcmd" in
        show)
            python3 - "$CONFIG_FILE" "$account" "$guild" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
account_id = sys.argv[2]
guild_filter = sys.argv[3] if len(sys.argv) > 3 else ""

try:
    with open(config_file) as f:
        config = json.load(f)
    acct = config.get("channels", {}).get("discord", {}).get("accounts", {}).get(account_id, {})
    guilds = acct.get("guilds", {})

    if not guilds:
        print(f"No guilds configured for account '{account_id}'")
        sys.exit(0)

    for gid, gcfg in guilds.items():
        if guild_filter and gid != guild_filter:
            continue
        users = gcfg.get("users", [])
        roles = gcfg.get("roles", [])
        print(f"Guild {gid}:")
        print(f"  users: {users if users else '(none)'}")
        print(f"  roles: {roles if roles else '(none)'}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
            ;;
        add)
            if [ -z "$guild" ]; then
                log_error "--guild is required for allowlist add"
                exit 1
            fi
            if [ -z "$user" ] && [ -z "$role" ]; then
                log_error "Specify --user <id> or --role <id>"
                exit 1
            fi
            if [ -n "$user" ]; then
                array_add "channels.discord.accounts.${account}.guilds.${guild}.users" "$user"
                log_success "Added user $user to guild $guild allowlist"
            fi
            if [ -n "$role" ]; then
                array_add "channels.discord.accounts.${account}.guilds.${guild}.roles" "$role"
                log_success "Added role $role to guild $guild allowlist"
            fi
            log_warn "Restart gateway to apply: openclaw gateway restart"
            ;;
        remove)
            if [ -z "$guild" ]; then
                log_error "--guild is required for allowlist remove"
                exit 1
            fi
            if [ -z "$user" ] && [ -z "$role" ]; then
                log_error "Specify --user <id> or --role <id>"
                exit 1
            fi
            if [ -n "$user" ]; then
                array_remove "channels.discord.accounts.${account}.guilds.${guild}.users" "$user"
                log_success "Removed user $user from guild $guild allowlist"
            fi
            if [ -n "$role" ]; then
                array_remove "channels.discord.accounts.${account}.guilds.${guild}.roles" "$role"
                log_success "Removed role $role from guild $guild allowlist"
            fi
            log_warn "Restart gateway to apply: openclaw gateway restart"
            ;;
        *)
            log_error "Unknown allowlist subcommand: $subcmd"
            log_info "Usage: manage-discord.sh allowlist {show|add|remove} [options]"
            exit 1
            ;;
    esac
}

# ─── guild ────────────────────────────────────────────────────────────────────

cmd_guild() {
    local subcmd="${1:-}"
    shift || true

    local account="" guild="" require_mention="true" users=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account)         account="$2";         shift 2 ;;
            --guild)           guild="$2";           shift 2 ;;
            --require-mention) require_mention="$2"; shift 2 ;;
            --users)           users="$2";           shift 2 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    [ -z "$account" ] && account=$(auto_detect_account)

    if [ -z "$guild" ]; then
        log_error "--guild is required"
        exit 1
    fi

    case "$subcmd" in
        add)
            local base="channels.discord.accounts.${account}.guilds.${guild}"
            config_set "${base}.requireMention" "$require_mention" --strict-json
            if [ -n "$users" ]; then
                # Build JSON array from comma-separated IDs
                USERS_JSON="["
                first=true
                IFS=',' read -ra ID_ARRAY <<< "$users"
                for uid in "${ID_ARRAY[@]}"; do
                    uid=$(echo "$uid" | xargs)
                    if [ -n "$uid" ]; then
                        $first || USERS_JSON+=","
                        USERS_JSON+="\"$uid\""
                        first=false
                    fi
                done
                USERS_JSON+="]"
                config_set "${base}.users" "$USERS_JSON" --strict-json
            fi
            log_success "Added guild $guild to account $account"
            log_warn "Restart gateway to apply: openclaw gateway restart"
            ;;
        remove)
            config_unset "channels.discord.accounts.${account}.guilds.${guild}"
            log_success "Removed guild $guild from account $account"
            log_warn "Restart gateway to apply: openclaw gateway restart"
            ;;
        *)
            log_error "Usage: manage-discord.sh guild {add|remove} --guild <id> [options]"
            exit 1
            ;;
    esac
}

# ─── channel ──────────────────────────────────────────────────────────────────

cmd_channel() {
    local subcmd="${1:-}"
    shift || true

    local account="" guild="" channel="" require_mention=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account)         account="$2";         shift 2 ;;
            --guild)           guild="$2";           shift 2 ;;
            --channel)         channel="$2";         shift 2 ;;
            --require-mention) require_mention="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    [ -z "$account" ] && account=$(auto_detect_account)

    if [ -z "$guild" ]; then
        log_error "--guild is required"
        exit 1
    fi

    case "$subcmd" in
        add)
            if [ -z "$channel" ]; then
                log_error "--channel is required"
                exit 1
            fi
            local base="channels.discord.accounts.${account}.guilds.${guild}.channels.${channel}"
            config_set "${base}.allow" "true" --strict-json
            if [ -n "$require_mention" ]; then
                config_set "${base}.requireMention" "$require_mention" --strict-json
            fi
            log_success "Added channel $channel to guild $guild"
            log_warn "When channels are configured, only listed channels are allowed."
            log_warn "Restart gateway to apply: openclaw gateway restart"
            ;;
        remove)
            if [ -z "$channel" ]; then
                log_error "--channel is required"
                exit 1
            fi
            config_unset "channels.discord.accounts.${account}.guilds.${guild}.channels.${channel}"
            log_success "Removed channel $channel from guild $guild"
            log_warn "Restart gateway to apply: openclaw gateway restart"
            ;;
        list)
            python3 - "$CONFIG_FILE" "$account" "$guild" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
account_id = sys.argv[2]
guild_id = sys.argv[3]

try:
    with open(config_file) as f:
        config = json.load(f)
    guild = config.get("channels", {}).get("discord", {}).get("accounts", {}).get(account_id, {}).get("guilds", {}).get(guild_id, {})
    channels = guild.get("channels", {})

    if not channels:
        print(f"No channel restrictions for guild {guild_id} (all channels allowed)")
        sys.exit(0)

    print(f"Channels for guild {guild_id} (account: {account_id}):")
    for ch_id, ch_cfg in channels.items():
        allow = ch_cfg.get("allow", True)
        mention = ch_cfg.get("requireMention", None)
        parts = [f"allow: {str(allow).lower()}"]
        if mention is not None:
            parts.append(f"requireMention: {str(mention).lower()}")
        print(f"  {ch_id} ({', '.join(parts)})")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
            ;;
        *)
            log_error "Usage: manage-discord.sh channel {add|remove|list} --guild <id> [options]"
            exit 1
            ;;
    esac
}

# ─── mention ──────────────────────────────────────────────────────────────────

cmd_mention() {
    local subcmd="${1:-}"
    shift || true

    local account="" guild="" channel=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account) account="$2"; shift 2 ;;
            --guild)   guild="$2";   shift 2 ;;
            --channel) channel="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    [ -z "$account" ] && account=$(auto_detect_account)

    if [ -z "$guild" ]; then
        log_error "--guild is required"
        exit 1
    fi

    local value
    case "$subcmd" in
        on)  value="true" ;;
        off) value="false" ;;
        *)
            log_error "Usage: manage-discord.sh mention {on|off} --guild <id> [--channel <id>]"
            exit 1
            ;;
    esac

    if [ -n "$channel" ]; then
        config_set "channels.discord.accounts.${account}.guilds.${guild}.channels.${channel}.requireMention" "$value" --strict-json
        log_success "Set requireMention=$value for channel $channel in guild $guild"
    else
        config_set "channels.discord.accounts.${account}.guilds.${guild}.requireMention" "$value" --strict-json
        log_success "Set requireMention=$value for guild $guild"
    fi
    log_warn "Restart gateway to apply: openclaw gateway restart"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main dispatch
# ═══════════════════════════════════════════════════════════════════════════════

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    list)      cmd_list "$@" ;;
    allowlist) cmd_allowlist "$@" ;;
    guild)     cmd_guild "$@" ;;
    channel)   cmd_channel "$@" ;;
    mention)   cmd_mention "$@" ;;
    -h|--help|help|"")
        show_help
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
