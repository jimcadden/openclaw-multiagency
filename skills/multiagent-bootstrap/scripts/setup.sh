#!/bin/bash
#
# multiagent-bootstrap: One-time setup for OpenClaw multi-agent workspace
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/agent-workspace}"
KIT_DIR="${KIT_DIR:-$WORKSPACE_DIR/kit}"
AGENT_NAME="${1:-}"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."
    
    if ! command -v openclaw &> /dev/null; then
        log_error "OpenClaw not found. Please install OpenClaw first."
        exit 1
    fi
    
    if [ ! -d "$KIT_DIR" ]; then
        log_error "Kit directory not found at $KIT_DIR"
        log_info "Did you add the submodule? Run:"
        log_info "  git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit"
        exit 1
    fi
    
    if [ ! -d "$WORKSPACE_DIR/.git" ]; then
        log_warn "No git repository found in $WORKSPACE_DIR"
        read -p "Initialize git repo? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            cd "$WORKSPACE_DIR"
            git init
            log_success "Git repo initialized"
        else
            log_error "Git is required for workspace management"
            exit 1
        fi
    fi
    
    log_success "Prerequisites OK"
}

# Create shared directory structure
setup_shared() {
    log_info "Creating shared directory structure..."
    
    mkdir -p "$WORKSPACE_DIR/shared/skills"
    
    # Symlink shared skills
    if [ ! -L "$WORKSPACE_DIR/shared/skills/multiagent-state-manager" ]; then
        ln -s "$KIT_DIR/skills/multiagent-state-manager" "$WORKSPACE_DIR/shared/skills/multiagent-state-manager"
        log_success "Linked multiagent-state-manager"
    fi
    
    if [ ! -L "$WORKSPACE_DIR/shared/skills/multiagent-telegram-setup" ]; then
        ln -s "$KIT_DIR/skills/multiagent-telegram-setup" "$WORKSPACE_DIR/shared/skills/multiagent-telegram-setup"
        log_success "Linked multiagent-telegram-setup"
    fi
}

# Get agent name from user or use default
get_agent_name() {
    if [ -z "$AGENT_NAME" ]; then
        echo
        log_info "What should we call your first agent?"
        read -p "Agent name [main]: " AGENT_NAME
        AGENT_NAME="${AGENT_NAME:-main}"
    fi
    
    # Validate name (alphanumeric, hyphen, underscore only)
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
    log_info "Creating agent workspace from template..."
    
    cp -r "$KIT_DIR/workspace-template" "$WORKSPACE_DIR/$AGENT_NAME"
    
    # Symlink shared skills into agent directory
    ln -s "../shared/skills/multiagent-state-manager" "$WORKSPACE_DIR/$AGENT_NAME/multiagent-state-manager"
    ln -s "../shared/skills/multiagent-telegram-setup" "$WORKSPACE_DIR/$AGENT_NAME/multiagent-telegram-setup"
    
    log_success "Agent workspace created at $WORKSPACE_DIR/$AGENT_NAME"
}

# Customize agent identity
customize_agent() {
    log_info "Let's customize your agent..."
    echo
    
    # Get user info
    read -p "Your name: " USER_NAME
    read -p "What should the agent call you? (e.g., Jim, boss, sir) [$USER_NAME]: " USER_CALL
    USER_CALL="${USER_CALL:-$USER_NAME}"
    
    # Get agent identity
    read -p "Agent name (how you address it): [JimClaw] " AGENT_ID_NAME
    AGENT_ID_NAME="${AGENT_ID_NAME:-JimClaw}"
    
    read -p "Agent emoji: [🤖] " AGENT_EMOJI
    AGENT_EMOJI="${AGENT_EMOJI:-🤖}"
    
    # Update USER.md
    cat > "$WORKSPACE_DIR/$AGENT_NAME/USER.md" << EOF
# USER.md - About Your Human

- **Name:** $USER_NAME
- **What to call them:** $USER_CALL
- **Pronouns:**
- **Timezone:**
- **Notes:**

## Context

_(What do they care about? What projects are they working on? What annoys them? What makes them laugh? Build this over time.)_
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
update_openclaw_config() {
    log_info "Updating OpenClaw configuration..."
    
    local CONFIG_FILE="$HOME/.openclaw/openclaw.json"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "OpenClaw config not found at $CONFIG_FILE"
        exit 1
    fi
    
    # Backup config
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Use Python to safely update JSON
    python3 << EOF
import json
import sys

config_file = "$CONFIG_FILE"
agent_id = "$AGENT_NAME"
workspace = "$WORKSPACE_DIR/$AGENT_NAME"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    # Ensure agents.list exists
    if 'agents' not in config:
        config['agents'] = {}
    if 'list' not in config['agents']:
        config['agents']['list'] = []
    
    # Check if agent already exists
    existing = [a for a in config['agents']['list'] if a.get('id') == agent_id]
    if existing:
        print(f"Agent '{agent_id}' already exists in config")
        sys.exit(0)
    
    # Add new agent
    config['agents']['list'].append({
        'id': agent_id,
        'workspace': workspace
    })
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"Added agent '{agent_id}' to OpenClaw config")
except Exception as e:
    print(f"Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    log_success "OpenClaw config updated"
}

# Prompt for Telegram setup
prompt_telegram() {
    echo
    log_info "Telegram Setup"
    log_info "--------------"
    read -p "Set up Telegram for this agent now? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Running Telegram setup..."
        if [ -f "$KIT_DIR/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py" ]; then
            python3 "$KIT_DIR/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py" --agent "$AGENT_NAME"
        else
            log_warn "Telegram setup script not found"
        fi
    else
        log_info "Skipped Telegram setup. Run later with:"
        log_info "  ./kit/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py"
    fi
}

# Initial git commit
git_commit() {
    log_info "Creating initial git commit..."
    
    cd "$WORKSPACE_DIR"
    
    # Create .gitignore if it doesn't exist
    if [ ! -f ".gitignore" ]; then
        cat > ".gitignore" << 'EOF'
# Runtime state (per-agent)
**/.openclaw/

# Editor
*.swp
*~
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
EOF
        log_success "Created .gitignore"
    fi
    
    git add -A
    git commit -m "[init] Bootstrap agent workspace

Agent: $AGENT_NAME
OpenClaw: $(openclaw version 2>/dev/null || echo 'unknown')"
    
    log_success "Initial commit created"
}

# Main
main() {
    echo
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  OpenClaw Multi-Agent Bootstrap                        ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo
    
    check_prereqs
    setup_shared
    get_agent_name
    create_agent
    customize_agent
    update_openclaw_config
    prompt_telegram
    git_commit
    
    echo
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Bootstrap Complete!                                   ║"
    echo "╠════════════════════════════════════════════════════════╣"
    echo "║  Next steps:                                           ║"
    echo "║    1. Restart OpenClaw: openclaw gateway restart       ║"
    echo "║    2. Verify agent: openclaw status                    ║"
    echo "║    3. Start chatting with your agent!                  ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo
}

main
