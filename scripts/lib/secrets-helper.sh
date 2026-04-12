#!/bin/bash
#
# secrets-helper.sh: Provider-aware secret persistence and SecretRef config helpers
#
# Source this file from setup/removal scripts. It wraps the openclaw config and
# secrets CLIs so callers don't need to know which secrets backend is active.
#
# Supported providers: env (default), file (JSON), exec (1Password/Vault/sops)
#
# SECURITY: This library intentionally has NO function that reads secret values.
# Agents must never retrieve raw tokens; they only see the env var *name* in
# the SecretRef object. persist_secret_value is write-only and intended for
# interactive human-operated setup scripts only.

# ─── Defaults ────────────────────────────────────────────────────────────────

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
OPENCLAW_ENV_FILE="${OPENCLAW_DIR}/.env"

# ─── Colors (only if not already defined by the sourcing script) ─────────────

_SH_BLUE="${BLUE:-\033[0;34m}"
_SH_GREEN="${GREEN:-\033[0;32m}"
_SH_YELLOW="${YELLOW:-\033[1;33m}"
_SH_RED="${RED:-\033[0;31m}"
_SH_NC="${NC:-\033[0m}"

_sh_info()  { echo -e "${_SH_BLUE}ℹ${_SH_NC} $1"; }
_sh_ok()    { echo -e "${_SH_GREEN}✓${_SH_NC} $1"; }
_sh_warn()  { echo -e "${_SH_YELLOW}⚠${_SH_NC} $1"; }
_sh_err()   { echo -e "${_SH_RED}✗${_SH_NC} $1"; }

# ─── detect_secrets_provider ─────────────────────────────────────────────────
#
# Reads secrets.providers.default.source from openclaw.json.
# Prints one of: env, file, exec
# Falls back to "env" when unconfigured or when openclaw CLI is unavailable.

detect_secrets_provider() {
    local source=""

    if command -v openclaw &>/dev/null; then
        source=$(openclaw config get secrets.providers.default.source 2>/dev/null || true)
    fi

    if [ -z "$source" ]; then
        # Try reading directly from JSON as fallback
        local config_file="$OPENCLAW_DIR/openclaw.json"
        if [ -f "$config_file" ] && command -v python3 &>/dev/null; then
            source=$(python3 -c "
import json, sys
try:
    with open('$config_file') as f:
        c = json.load(f)
    print(c.get('secrets',{}).get('providers',{}).get('default',{}).get('source',''))
except Exception:
    pass
" 2>/dev/null || true)
        fi
    fi

    case "$source" in
        env|file|exec) echo "$source" ;;
        *) echo "env" ;;
    esac
}

# ─── persist_secret_value ────────────────────────────────────────────────────
#
# Write-only. Stores a secret value through the detected provider backend.
# Only called during interactive human-operated setup -- never by agents.
#
# Usage: persist_secret_value <provider_type> <key> <value>
#
# env:  upserts 'export KEY="VALUE"' in ~/.openclaw/.env (chmod 600)
# file: writes into the provider's configured JSON file at /<key> pointer
# exec: prints instructions for the operator; returns 1 so caller can handle

persist_secret_value() {
    local provider_type="$1"
    local key="$2"
    local value="$3"

    case "$provider_type" in
        env)
            _persist_env_secret "$key" "$value"
            ;;
        file)
            _persist_file_secret "$key" "$value"
            ;;
        exec)
            echo
            _sh_warn "Exec secrets provider detected (1Password, Vault, sops, etc.)"
            _sh_info "Store this secret in your vault under the key: $key"
            _sh_info "Then validate with: openclaw config set --dry-run ..."
            echo
            return 1
            ;;
        *)
            _sh_err "Unknown secrets provider type: $provider_type"
            return 1
            ;;
    esac
}

# ─── write_secret_ref ────────────────────────────────────────────────────────
#
# Writes a SecretRef to openclaw.json via the openclaw config CLI.
#
# Usage: write_secret_ref <config_path> <provider_name> <source_type> <ref_id>
# Example: write_secret_ref "channels.discord.accounts.dev.token" "default" "env" "DISCORD_BOT_TOKEN_DEV"

write_secret_ref() {
    local config_path="$1"
    local provider_name="$2"
    local source_type="$3"
    local ref_id="$4"

    if command -v openclaw &>/dev/null; then
        openclaw config set "$config_path" \
            --ref-provider "$provider_name" \
            --ref-source "$source_type" \
            --ref-id "$ref_id" 2>&1
        return $?
    else
        _sh_warn "openclaw CLI not found -- writing SecretRef via Python fallback"
        _write_secret_ref_python "$config_path" "$provider_name" "$source_type" "$ref_id"
        return $?
    fi
}

# ─── validate_secret_ref ─────────────────────────────────────────────────────
#
# Validates that a SecretRef at the given config path resolves successfully.
#
# Usage: validate_secret_ref <config_path> <provider_name> <source_type> <ref_id>

validate_secret_ref() {
    local config_path="$1"
    local provider_name="$2"
    local source_type="$3"
    local ref_id="$4"

    if ! command -v openclaw &>/dev/null; then
        _sh_warn "openclaw CLI not found -- skipping dry-run validation"
        return 0
    fi

    local output
    output=$(openclaw config set "$config_path" \
        --ref-provider "$provider_name" \
        --ref-source "$source_type" \
        --ref-id "$ref_id" \
        --dry-run 2>&1)
    local rc=$?

    if [ $rc -ne 0 ]; then
        _sh_warn "SecretRef dry-run validation failed:"
        echo "$output" >&2
        _sh_info "The SecretRef was written to config, but the provider cannot resolve it yet."
        _sh_info "Ensure the secret value is available to the '$source_type' provider, then run:"
        _sh_info "  openclaw secrets audit --check"
    fi

    return $rc
}

# ─── report_orphaned_ref ─────────────────────────────────────────────────────
#
# Reports a SecretRef that is no longer needed after account removal.
# Does NOT read or delete the actual secret value.
#
# Usage: report_orphaned_ref <ref_id> <source_type>

report_orphaned_ref() {
    local ref_id="$1"
    local source_type="${2:-env}"

    _sh_warn "Orphaned secret reference: $ref_id (source: $source_type)"
    _sh_info "This secret is no longer referenced in openclaw.json."
    _sh_info "Clean up with: openclaw secrets audit --check"
}

# ─── Internal: env provider persistence ──────────────────────────────────────

_persist_env_secret() {
    local key="$1"
    local value="$2"

    # Ensure directory exists
    if [ ! -d "$OPENCLAW_DIR" ]; then
        mkdir -p "$OPENCLAW_DIR"
    fi

    # Escape double quotes in value for safe embedding
    local escaped_value="${value//\"/\\\"}"
    local line="export ${key}=\"${escaped_value}\""

    if [ -f "$OPENCLAW_ENV_FILE" ]; then
        # Remove existing line for this key (if any) then append
        local tmp
        tmp=$(mktemp)
        grep -v "^export ${key}=" "$OPENCLAW_ENV_FILE" > "$tmp" 2>/dev/null || true
        echo "$line" >> "$tmp"
        mv "$tmp" "$OPENCLAW_ENV_FILE"
    else
        echo "$line" > "$OPENCLAW_ENV_FILE"
    fi

    chmod 600 "$OPENCLAW_ENV_FILE"

    # Export into current shell so subsequent dry-run validation works
    export "${key}=${value}"

    _sh_ok "Secret stored in $OPENCLAW_ENV_FILE as $key"
}

# ─── Internal: file provider persistence ─────────────────────────────────────

_persist_file_secret() {
    local key="$1"
    local value="$2"

    # Read provider path from config
    local file_path=""
    if command -v openclaw &>/dev/null; then
        file_path=$(openclaw config get secrets.providers.default.path 2>/dev/null || true)
    fi

    if [ -z "$file_path" ]; then
        local config_file="$OPENCLAW_DIR/openclaw.json"
        if [ -f "$config_file" ] && command -v python3 &>/dev/null; then
            file_path=$(python3 -c "
import json
try:
    with open('$config_file') as f:
        c = json.load(f)
    p = c.get('secrets',{}).get('providers',{}).get('default',{}).get('path','')
    print(p.replace('~', '$HOME') if p.startswith('~') else p)
except Exception:
    pass
" 2>/dev/null || true)
        fi
    fi

    if [ -z "$file_path" ]; then
        _sh_err "File provider configured but no path found in secrets.providers.default.path"
        return 1
    fi

    # Expand ~ in path
    file_path="${file_path/#\~/$HOME}"

    if ! command -v python3 &>/dev/null; then
        _sh_err "python3 required for file provider secret persistence"
        return 1
    fi

    python3 - "$file_path" "$key" "$value" << 'PYEOF'
import json, sys, os

file_path = sys.argv[1]
key = sys.argv[2]
value = sys.argv[3]

try:
    if os.path.exists(file_path):
        with open(file_path) as f:
            data = json.load(f)
    else:
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        data = {}

    data[key] = value

    with open(file_path, 'w') as f:
        json.dump(data, f, indent=2)
    os.chmod(file_path, 0o600)

    print(f"Secret stored in {file_path} as {key}")
except Exception as e:
    print(f"Error writing to file provider: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ─── Internal: Python fallback for SecretRef writing ─────────────────────────

_write_secret_ref_python() {
    local config_path="$1"
    local provider_name="$2"
    local source_type="$3"
    local ref_id="$4"
    local config_file="$OPENCLAW_DIR/openclaw.json"

    if [ ! -f "$config_file" ]; then
        _sh_err "openclaw.json not found at $config_file"
        return 1
    fi

    python3 - "$config_file" "$config_path" "$provider_name" "$source_type" "$ref_id" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
config_path = sys.argv[2]
provider_name = sys.argv[3]
source_type = sys.argv[4]
ref_id = sys.argv[5]

ref_obj = {"source": source_type, "provider": provider_name, "id": ref_id}

try:
    with open(config_file) as f:
        config = json.load(f)

    parts = config_path.split(".")
    obj = config
    for part in parts[:-1]:
        obj = obj.setdefault(part, {})
    obj[parts[-1]] = ref_obj

    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)

    print(f"Wrote SecretRef at {config_path}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}
