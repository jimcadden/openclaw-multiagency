#!/bin/bash
#
# set-agent-sandbox.sh: Change the sandbox mode for an existing agent
#
# Usage: ./set-agent-sandbox.sh --agent <agent-id> --mode <off|inherit>
#
#   off     — agent is never sandboxed (sets sandbox.mode = "off" on the entry)
#   inherit — agent follows agents.defaults.sandbox.mode (removes per-agent override)

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

# ─── Defaults ─────────────────────────────────────────────────────────────────

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_WORKSPACE="$(dirname "$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")")"
KIT_DIR="${KIT_DIR:-$AUTO_WORKSPACE/kit}"
if [ ! -d "$KIT_DIR" ]; then KIT_DIR="${KIT_DIR:-$HOME/workspaces/kit}"; fi

CONFIG_HELPER="$KIT_DIR/scripts/lib/config-helper.sh"
if [ -f "$CONFIG_HELPER" ]; then
    source "$CONFIG_HELPER"
fi
AGENT_ID=""
MODE=""

# ─── Args ─────────────────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 --agent <agent-id> --mode <off|inherit>"
    echo
    echo "  --agent    ID of the agent to update (must exist in openclaw.json)"
    echo "  --mode     off      — disable sandboxing for this agent"
    echo "             inherit  — remove override; agent follows global default"
    echo
    echo "Environment:"
    echo "  OPENCLAW_DIR  path to OpenClaw config dir (default: ~/.openclaw)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent) AGENT_ID="$2"; shift 2 ;;
        --mode)  MODE="$2";     shift 2 ;;
        -h|--help) usage ;;
        *) log_error "Unknown argument: $1"; usage ;;
    esac
done

# ─── Validate ─────────────────────────────────────────────────────────────────

if [ -z "$AGENT_ID" ]; then
    log_error "--agent is required"
    usage
fi

if [ -z "$MODE" ]; then
    log_error "--mode is required"
    usage
fi

if [[ "$MODE" != "off" && "$MODE" != "inherit" ]]; then
    log_error "--mode must be 'off' or 'inherit', got: $MODE"
    usage
fi

CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "openclaw.json not found at $CONFIG_FILE"
    log_info "Set OPENCLAW_DIR if your config lives elsewhere."
    exit 1
fi

# ─── Update ───────────────────────────────────────────────────────────────────

# Find the agent index in agents.list
IDX=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    c = json.load(f)
for i, a in enumerate(c.get('agents',{}).get('list',[])):
    if a.get('id') == '$AGENT_ID':
        print(i); break
else:
    import sys
    known = [a.get('id','') for a in c.get('agents',{}).get('list',[])]
    print(f\"Agent '$AGENT_ID' not found. Known: {', '.join(known) if known else '(none)'}\", file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [ $? -ne 0 ] || [ -z "$IDX" ]; then
    log_error "$IDX"
    exit 1
fi

if [ "$MODE" = "off" ]; then
    oc_config_set_json "agents.list[$IDX].sandbox.mode" '"off"'
else
    oc_config_unset "agents.list[$IDX].sandbox"
fi

log_success "openclaw.json updated"
log_warn "Restart the gateway to apply: openclaw gateway restart"
