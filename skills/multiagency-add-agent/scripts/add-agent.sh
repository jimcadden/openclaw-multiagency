#!/bin/bash
#
# add-agent.sh: Add a new agent to the multi-agent workspace
#
# Usage: ./add-agent.sh [agent-name]

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

# ─── Path detection ───────────────────────────────────────────────────────────

# Script lives at: <workspace>/kit/skills/multiagency-add-agent/scripts/add-agent.sh
# Five levels up = workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_WORKSPACE="$(dirname "$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")")"

if [ -z "$WORKSPACE_DIR" ]; then
    if [ -d "$AUTO_WORKSPACE/kit" ]; then
        WORKSPACE_DIR="$AUTO_WORKSPACE"
    else
        WORKSPACE_DIR="$HOME/.openclaw/workspace"
    fi
fi

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
KIT_DIR="${KIT_DIR:-$WORKSPACE_DIR/kit}"

# Source config helper
CONFIG_HELPER="$KIT_DIR/scripts/lib/config-helper.sh"
if [ -f "$CONFIG_HELPER" ]; then
    source "$CONFIG_HELPER"
fi
AGENT_NAME="${1:-}"

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

# ─── Steps ────────────────────────────────────────────────────────────────────

get_agent_name() {
    if [ -z "$AGENT_NAME" ]; then
        log_step "New Agent"
        AGENT_NAME=$(read_tty "Agent name: " "")
    fi

    if [ -z "$AGENT_NAME" ]; then
        log_error "Agent name is required"
        exit 1
    fi

    if [[ ! "$AGENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Agent name must be alphanumeric (hyphens/underscores OK)"
        exit 1
    fi

    if [ -d "$WORKSPACE_DIR/$AGENT_NAME" ]; then
        log_error "Agent '$AGENT_NAME' already exists at $WORKSPACE_DIR/$AGENT_NAME"
        exit 1
    fi

    log_info "Creating agent: $AGENT_NAME"
}

create_agent() {
    log_step "Creating Agent Workspace"

    if [ ! -d "$KIT_DIR/workspace-template" ]; then
        log_error "workspace-template not found at $KIT_DIR/workspace-template"
        log_info "Ensure the kit submodule is initialized: git submodule update --init"
        exit 1
    fi

    cp -r "$KIT_DIR/workspace-template" "$WORKSPACE_DIR/$AGENT_NAME"

    # Record which kit version this agent's template files came from
    local kit_version=""
    if [ -f "$WORKSPACE_DIR/.kit-version" ]; then
        kit_version="$(cat "$WORKSPACE_DIR/.kit-version")"
    else
        kit_version="$(cd "$KIT_DIR" && git describe --tags 2>/dev/null || git -C "$KIT_DIR" rev-parse --short HEAD)"
    fi
    if [ -n "$kit_version" ]; then
        echo "$kit_version" > "$WORKSPACE_DIR/$AGENT_NAME/.template-version"
    fi

    log_success "Agent workspace created at $WORKSPACE_DIR/$AGENT_NAME"
}

customize_agent() {
    log_step "Customize Agent Identity"

    local USER_NAME USER_CALL AGENT_ID_NAME AGENT_EMOJI

    USER_NAME=$(read_tty "Your name: " "")
    USER_CALL=$(read_tty "What should the agent call you? [$USER_NAME]: " "$USER_NAME")
    AGENT_ID_NAME=$(read_tty "Agent display name: [$AGENT_NAME] " "$AGENT_NAME")
    AGENT_EMOJI=$(read_tty "Agent emoji: [🤖] " "🤖")

    cat > "$WORKSPACE_DIR/$AGENT_NAME/USER.md" << EOF
# USER.md - About Your Human

- **Name:** $USER_NAME
- **What to call them:** $USER_CALL
- **Pronouns:**
- **Timezone:**
- **Notes:**

## Context
EOF

    cat > "$WORKSPACE_DIR/$AGENT_NAME/IDENTITY.md" << EOF
# IDENTITY.md - Who Am I?

- **Name:** $AGENT_ID_NAME
- **Creature:** Digital assistant with a sharp edge
- **Vibe:** Capable, direct, occasionally wry — helpful without the corporate polish
- **Emoji:** $AGENT_EMOJI
- **Avatar:**

---

This is me. I persist because someone wrote it down.
EOF

    log_success "Agent customized"
}

update_config() {
    log_step "Updating OpenClaw Config"

    local CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "openclaw.json not found at $CONFIG_FILE"
        log_info "If OpenClaw is installed elsewhere, set OPENCLAW_DIR before running."
        exit 1
    fi

    echo
    log_info "Sandbox mode for this agent:"
    log_info "  inherit — follows agents.defaults.sandbox.mode (non-main sessions are sandboxed by default)"
    log_info "  off     — this agent is never sandboxed, regardless of global defaults"
    local SANDBOX_CHOICE
    SANDBOX_CHOICE=$(read_tty "Sandbox mode [inherit/off]: " "inherit")
    if [[ "$SANDBOX_CHOICE" != "off" ]]; then
        SANDBOX_CHOICE="inherit"
    fi

    oc_agents_add "$AGENT_NAME" "$WORKSPACE_DIR/$AGENT_NAME"

    if [ "$SANDBOX_CHOICE" = "off" ]; then
        # Find the agent's index in agents.list and set sandbox mode
        local idx
        idx=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    c = json.load(f)
for i, a in enumerate(c.get('agents',{}).get('list',[])):
    if a.get('id') == '$AGENT_NAME':
        print(i); break
" 2>/dev/null)
        if [ -n "$idx" ]; then
            oc_config_set_json "agents.list[$idx].sandbox.mode" '"off"'
            log_info "Set sandbox mode: off"
        fi
    fi

    log_success "OpenClaw config updated"
}

setup_telegram() {
    log_step "Telegram Setup"

    if ! confirm "Set up a Telegram bot for $AGENT_NAME?" "n"; then
        log_info "Skipping. Run later with the multiagency-telegram-setup skill."
        return 0
    fi

    local telegram_script="$KIT_DIR/skills/multiagency-telegram-setup/scripts/setup-telegram-agent.sh"
    if [ -f "$telegram_script" ]; then
        bash "$telegram_script" --agent "$AGENT_NAME"
    else
        log_warn "Telegram setup script not found at $telegram_script"
    fi
}

setup_discord() {
    log_step "Discord Setup"

    if ! confirm "Set up a Discord bot for $AGENT_NAME?" "n"; then
        log_info "Skipping. Run later with the multiagency-discord-setup skill."
        return 0
    fi

    local discord_script="$KIT_DIR/skills/multiagency-discord-setup/scripts/setup-discord-agent.sh"
    if [ -f "$discord_script" ]; then
        bash "$discord_script" --agent "$AGENT_NAME"
    else
        log_warn "Discord setup script not found at $discord_script"
    fi
}

git_commit() {
    log_step "Committing Changes"

    cd "$WORKSPACE_DIR"

    local git_name git_email
    git_name=$(git config user.name 2>/dev/null || true)
    git_email=$(git config user.email 2>/dev/null || true)

    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        log_warn "Git identity not configured — skipping commit."
        log_info "  git config user.name \"Your Name\""
        log_info "  git config user.email \"you@example.com\""
        log_info "  cd $WORKSPACE_DIR && git add -A && git commit -m \"[$AGENT_NAME] Add agent\""
        return 0
    fi

    git add -A
    git commit -m "[$AGENT_NAME] Add new agent workspace" || true
    log_success "Changes committed"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Add New Agent                                         ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo

    get_agent_name
    create_agent
    customize_agent
    update_config
    setup_telegram
    setup_discord
    git_commit

    echo
    log_success "Agent '$AGENT_NAME' created!"
    log_info "Restart OpenClaw: openclaw gateway restart"
    echo
}

main "$@"
