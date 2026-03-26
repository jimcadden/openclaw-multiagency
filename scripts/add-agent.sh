#!/bin/bash
#
# Add a new agent to the multi-agent workspace
# Usage: ./add-agent.sh [agent-name]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
WORKSPACE_DIR="${WORKSPACE_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/workspaces")}"
KIT_DIR="${KIT_DIR:-$WORKSPACE_DIR/kit}"
AGENT_NAME="${1:-}"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo; echo -e "${CYAN}▶ $1${NC}"; }

# Input helper - reads from terminal even when piped
read_tty() {
    local prompt="$1"
    local default="${2:-}"
    local input=""
    
    printf "%s" "$prompt" >&2
    
    if [ -t 0 ]; then
        IFS= read -r input
    elif [ -r /dev/tty ]; then
        IFS= read -r input < /dev/tty
    else
        input=""
    fi
    
    if [ -z "$input" ] && [ -n "$default" ]; then
        input="$default"
    fi
    
    printf "%s" "$input"
}

# Yes/no prompt
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local yn="[y/N]"
    
    if [ "$default" = "y" ]; then
        yn="[Y/n]"
    fi
    
    local input
    input=$(read_tty "$prompt $yn " "")
    
    if [ -z "$input" ]; then
        input="$default"
    fi
    
    [[ "$input" =~ ^[Yy]$ ]]
}

# Get agent name
get_agent_name() {
    if [ -z "$AGENT_NAME" ]; then
        log_step "New Agent"
        local input
        input=$(read_tty "Agent name: " "")
        AGENT_NAME="$input"
    fi
    
    if [ -z "$AGENT_NAME" ]; then
        log_error "Agent name is required"
        exit 1
    fi
    
    # Validate name
    if [[ ! "$AGENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Agent name must be alphanumeric (with hyphens/underscores)"
        exit 1
    fi
    
    if [ -d "$WORKSPACE_DIR/$AGENT_NAME" ]; then
        log_error "Agent '$AGENT_NAME' already exists"
        exit 1
    fi
    
    log_info "Creating agent: $AGENT_NAME"
}

# Create agent from template
create_agent() {
    log_step "Creating Agent Workspace"
    
    cp -r "$KIT_DIR/workspace-template" "$WORKSPACE_DIR/$AGENT_NAME"
    
    # Symlink shared skills
    ln -s "../shared/skills/multiagent-state-manager" "$WORKSPACE_DIR/$AGENT_NAME/multiagent-state-manager"
    ln -s "../shared/skills/multiagent-telegram-setup" "$WORKSPACE_DIR/$AGENT_NAME/multiagent-telegram-setup"
    
    log_success "Agent workspace created at $WORKSPACE_DIR/$AGENT_NAME"
}

# Customize agent identity
customize_agent() {
    log_step "Customize Agent Identity"
    
    local USER_NAME USER_CALL AGENT_ID_NAME AGENT_EMOJI
    
    USER_NAME=$(read_tty "Your name: " "")
    USER_CALL=$(read_tty "What should the agent call you? [$USER_NAME]: " "$USER_NAME")
    AGENT_ID_NAME=$(read_tty "Agent name (how you address it): [${AGENT_NAME}Bot] " "${AGENT_NAME}Bot")
    AGENT_EMOJI=$(read_tty "Agent emoji: [🤖] " "🤖")
    
    # Update USER.md
    cat > "$WORKSPACE_DIR/$AGENT_NAME/USER.md" << EOF
# USER.md - About Your Human

- **Name:** $USER_NAME
- **What to call them:** $USER_CALL
- **Pronouns:**
- **Timezone:**
- **Notes:**

## Context
EOF
    
    # Update IDENTITY.md
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

# Update OpenClaw config
update_config() {
    log_step "Updating OpenClaw Config"
    
    local CONFIG_FILE="$HOME/.openclaw/openclaw.json"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "OpenClaw config not found"
        exit 1
    fi
    
    python3 << EOF
import json
import sys

config_file = "$CONFIG_FILE"
agent_id = "$AGENT_NAME"
workspace = "$WORKSPACE_DIR/$AGENT_NAME"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    if 'agents' not in config:
        config['agents'] = {}
    if 'list' not in config['agents']:
        config['agents']['list'] = []
    
    existing = [a for a in config['agents']['list'] if a.get('id') == agent_id]
    if existing:
        print(f"Agent '{agent_id}' already exists in config")
        sys.exit(0)
    
    config['agents']['list'].append({
        'id': agent_id,
        'workspace': workspace
    })
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"Added agent '{agent_id}' to config")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    log_success "OpenClaw config updated"
}

# Prompt for Telegram setup
setup_telegram() {
    log_step "Telegram Setup"
    
    if ! confirm "Set up a Telegram bot for $AGENT_NAME?" "n"; then
        log_info "Skipping Telegram. Run later with:"
        log_info "  python3 $KIT_DIR/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py --agent $AGENT_NAME"
        return 0
    fi
    
    if [ -f "$KIT_DIR/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py" ]; then
        python3 "$KIT_DIR/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py" --agent "$AGENT_NAME"
    else
        log_warn "Telegram setup script not found"
    fi
}

# Git commit
git_commit() {
    log_step "Committing Changes"
    
    cd "$WORKSPACE_DIR"
    git add -A
    git commit -m "[$AGENT_NAME] Add new agent workspace" || true
    
    log_success "Changes committed"
}

# Main
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
    git_commit
    
    echo
    log_success "Agent '$AGENT_NAME' created!"
    log_info "Restart OpenClaw: openclaw gateway restart"
    echo
}

main "$@"
