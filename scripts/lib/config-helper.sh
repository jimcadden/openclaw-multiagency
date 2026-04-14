#!/bin/bash
#
# config-helper.sh: CLI wrapper functions for openclaw config and agents commands
#
# Source this file from kit scripts to replace embedded Python JSON manipulation
# with openclaw CLI calls. Every function requires the openclaw CLI on PATH.
#
# Functions:
#   require_openclaw_cli       - verify openclaw is available
#   oc_agents_add              - register a new agent
#   oc_agents_bind             - create a channel binding for an agent
#   oc_agents_unbind_all       - remove all bindings for an agent
#   oc_agents_list_ids         - list agent IDs
#   oc_agents_exists           - check if agent exists in config
#   oc_config_set              - set a config value
#   oc_config_set_json         - set a config value with --strict-json
#   oc_config_get              - get a config value as JSON
#   oc_config_unset            - remove a config key
#   oc_config_set_if_missing   - set a value only if the key doesn't exist
#   oc_array_add_if_absent     - append an element to a JSON array if not present
#   oc_config_read_agents      - read agent IDs from config (Python fallback for reads)
#   oc_config_read_json        - read a JSON value from config

# ─── Defaults ────────────────────────────────────────────────────────────────

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

# ─── Internal colors (only if not already set) ───────────────────────────────

_CH_BLUE="${BLUE:-\033[0;34m}"
_CH_GREEN="${GREEN:-\033[0;32m}"
_CH_YELLOW="${YELLOW:-\033[1;33m}"
_CH_RED="${RED:-\033[0;31m}"
_CH_NC="${NC:-\033[0m}"

_ch_info()  { echo -e "${_CH_BLUE}ℹ${_CH_NC} $1"; }
_ch_ok()    { echo -e "${_CH_GREEN}✓${_CH_NC} $1"; }
_ch_warn()  { echo -e "${_CH_YELLOW}⚠${_CH_NC} $1"; }
_ch_err()   { echo -e "${_CH_RED}✗${_CH_NC} $1"; }

# ─── require_openclaw_cli ────────────────────────────────────────────────────

require_openclaw_cli() {
    if ! command -v openclaw &>/dev/null; then
        _ch_err "openclaw CLI not found on PATH"
        _ch_info "Install: https://docs.openclaw.ai/getting-started"
        return 1
    fi
}

# ─── Agents commands ─────────────────────────────────────────────────────────

oc_agents_add() {
    local name="$1"
    local workspace="$2"

    if ! command -v openclaw &>/dev/null; then
        _oc_agents_add_fallback "$name" "$workspace"
        return $?
    fi

    openclaw agents add "$name" --workspace "$workspace" --non-interactive 2>&1
}

oc_agents_bind() {
    local agent="$1"
    local channel_account="$2"

    if ! command -v openclaw &>/dev/null; then
        _oc_agents_bind_fallback "$agent" "$channel_account"
        return $?
    fi

    openclaw agents bind --agent "$agent" --bind "$channel_account" 2>&1
}

oc_agents_unbind_all() {
    local agent="$1"

    if ! command -v openclaw &>/dev/null; then
        _ch_warn "openclaw CLI not available -- unbind manually"
        return 1
    fi

    openclaw agents unbind --agent "$agent" --all 2>&1
}

oc_agents_list_ids() {
    if command -v openclaw &>/dev/null; then
        openclaw agents list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    agents = data if isinstance(data, list) else data.get('agents', [])
    for a in agents:
        aid = a.get('id', '') if isinstance(a, dict) else ''
        if aid: print(aid)
except Exception:
    pass
" 2>/dev/null
    else
        _oc_read_agent_ids_fallback
    fi
}

oc_agents_exists() {
    local name="$1"
    oc_agents_list_ids 2>/dev/null | grep -qx "$name"
}

# ─── Config set/get/unset ────────────────────────────────────────────────────

oc_config_set() {
    local path="$1"
    local value="$2"

    if command -v openclaw &>/dev/null; then
        openclaw config set "$path" "$value" 2>&1
    else
        _oc_config_set_fallback "$path" "$value" "string"
    fi
}

oc_config_set_json() {
    local path="$1"
    local value="$2"

    if command -v openclaw &>/dev/null; then
        openclaw config set "$path" "$value" --strict-json 2>&1
    else
        _oc_config_set_fallback "$path" "$value" "json"
    fi
}

oc_config_get() {
    local path="$1"

    if command -v openclaw &>/dev/null; then
        openclaw config get "$path" --json 2>/dev/null
    else
        _oc_config_get_fallback "$path"
    fi
}

oc_config_unset() {
    local path="$1"

    if command -v openclaw &>/dev/null; then
        openclaw config unset "$path" 2>&1
    else
        _oc_config_unset_fallback "$path"
    fi
}

# ─── Conditional set ─────────────────────────────────────────────────────────

oc_config_set_if_missing() {
    local path="$1"
    local value="$2"
    local mode="${3:-json}"

    local current
    current=$(oc_config_get "$path" 2>/dev/null)

    if [ -z "$current" ] || [ "$current" = "null" ] || [ "$current" = "undefined" ]; then
        if [ "$mode" = "json" ]; then
            oc_config_set_json "$path" "$value"
        else
            oc_config_set "$path" "$value"
        fi
        return $?
    else
        _ch_info "$path already set"
        return 0
    fi
}

# ─── Array add-if-absent ─────────────────────────────────────────────────────
#
# Reads a JSON array at the given config path, appends the value if not present,
# then writes the full array back.

oc_array_add_if_absent() {
    local path="$1"
    local value="$2"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    if [ ! -f "$config_file" ]; then
        _ch_err "openclaw.json not found at $config_file"
        return 1
    fi

    python3 - "$config_file" "$path" "$value" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
path = sys.argv[2]
new_value = sys.argv[3]

try:
    parsed_value = json.loads(new_value)
except (json.JSONDecodeError, ValueError):
    parsed_value = new_value

try:
    with open(config_file) as f:
        config = json.load(f)

    parts = path.split(".")
    obj = config
    for part in parts[:-1]:
        obj = obj.setdefault(part, {})

    arr = obj.get(parts[-1], [])
    if not isinstance(arr, list):
        arr = []

    if parsed_value not in arr:
        arr.append(parsed_value)
        obj[parts[-1]] = arr
        with open(config_file, "w") as f:
            json.dump(config, f, indent=2)
        print(f"Added to {path}")
    else:
        print(f"{path} already contains value")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ─── Python fallbacks for environments without openclaw CLI ──────────────────

_oc_agents_add_fallback() {
    local name="$1"
    local workspace="$2"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    [ -f "$config_file" ] || return 1

    python3 - "$config_file" "$name" "$workspace" << 'PYEOF'
import json, sys

config_file, agent_id, workspace = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(config_file) as f:
        config = json.load(f)

    agents = config.setdefault("agents", {}).setdefault("list", [])
    if not any(a.get("id") == agent_id for a in agents):
        agents.append({"id": agent_id, "workspace": workspace})
        with open(config_file, "w") as f:
            json.dump(config, f, indent=2)
        print(f"Added agent '{agent_id}' to agents.list")
    else:
        print(f"Agent '{agent_id}' already in agents.list")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

_oc_agents_bind_fallback() {
    local agent="$1"
    local channel_account="$2"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    [ -f "$config_file" ] || return 1

    local channel="${channel_account%%:*}"
    local account_id="${channel_account#*:}"

    python3 - "$config_file" "$agent" "$channel" "$account_id" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
agent_id = sys.argv[2]
channel = sys.argv[3]
account_id = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != sys.argv[3] else ""

try:
    with open(config_file) as f:
        config = json.load(f)

    bindings = config.setdefault("bindings", [])
    match = {"channel": channel}
    if account_id:
        match["accountId"] = account_id

    exists = any(
        b.get("agentId") == agent_id and
        b.get("match", {}).get("channel") == channel and
        b.get("match", {}).get("accountId", "") == account_id
        for b in bindings
    )
    if not exists:
        bindings.append({"agentId": agent_id, "match": match})
        with open(config_file, "w") as f:
            json.dump(config, f, indent=2)
        print(f"Added binding: {agent_id} <-> {channel}:{account_id}")
    else:
        print(f"Binding already exists")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

_oc_read_agent_ids_fallback() {
    local config_file="${OPENCLAW_DIR}/openclaw.json"
    [ -f "$config_file" ] || return 0

    python3 -c "
import json
try:
    with open('$config_file') as f:
        c = json.load(f)
    for a in c.get('agents', {}).get('list', []):
        aid = a.get('id', '')
        if aid: print(aid)
except Exception:
    pass
" 2>/dev/null
}

_oc_config_set_fallback() {
    local path="$1"
    local value="$2"
    local mode="$3"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    [ -f "$config_file" ] || return 1

    python3 - "$config_file" "$path" "$value" "$mode" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
path = sys.argv[2]
value = sys.argv[3]
mode = sys.argv[4] if len(sys.argv) > 4 else "string"

if mode == "json":
    try:
        parsed = json.loads(value)
    except (json.JSONDecodeError, ValueError):
        parsed = value
else:
    parsed = value

try:
    with open(config_file) as f:
        config = json.load(f)
    parts = path.split(".")
    obj = config
    for part in parts[:-1]:
        obj = obj.setdefault(part, {})
    obj[parts[-1]] = parsed
    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)
    print(f"Set {path}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

_oc_config_get_fallback() {
    local path="$1"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    [ -f "$config_file" ] || return 1

    python3 -c "
import json, sys
try:
    with open('$config_file') as f:
        c = json.load(f)
    parts = '$path'.split('.')
    obj = c
    for p in parts:
        if isinstance(obj, dict):
            obj = obj.get(p)
        else:
            obj = None
            break
    if obj is not None:
        print(json.dumps(obj))
    else:
        print('null')
except Exception:
    print('null')
" 2>/dev/null
}

_oc_config_unset_fallback() {
    local path="$1"
    local config_file="${OPENCLAW_DIR}/openclaw.json"

    [ -f "$config_file" ] || return 1

    python3 - "$config_file" "$path" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
path = sys.argv[2]

try:
    with open(config_file) as f:
        config = json.load(f)
    parts = path.split(".")
    obj = config
    for part in parts[:-1]:
        if part not in obj:
            sys.exit(0)
        obj = obj[part]
    if parts[-1] in obj:
        del obj[parts[-1]]
        with open(config_file, "w") as f:
            json.dump(config, f, indent=2)
        print(f"Unset {path}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}
