#!/bin/bash
#
# multiagent-bootstrap: One-time setup for OpenClaw multi-agent workspace
#
# Usage: ./setup.sh [agent-name]
#        ./setup.sh --dry-run [agent-name]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
DRY_RUN=false
AGENT_NAME=""

for arg in "$@"; do
    case $arg in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        *)
            AGENT_NAME="$arg"
            shift
            ;;
    esac
done

# Paths
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspaces}"
KIT_DIR="${KIT_DIR:-$WORKSPACE_DIR/kit}"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_tip() { echo -e "${CYAN}💡${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_dry() { echo -e "${CYAN}[DRY RUN]${NC} $1"; }

# Check for existing agents (migration scenario)
check_existing_agents() {
    # Look for common agent workspace patterns
    local existing_agents=()
    
    for dir in "$WORKSPACE_DIR"/*/; do
        if [ -d "$dir" ] && [ -f "$dir/IDENTITY.md" ] && [ -f "$dir/SOUL.md" ]; then
            existing_agents+=("$(basename "$dir")")
        fi
    done
    
    if [ ${#existing_agents[@]} -gt 0 ]; then
        echo
        log_warn "Existing agent workspaces detected!"
        echo
        echo "  Found: ${existing_agents[*]}"
        echo
        log_info "Bootstrap is for fresh installs only."
        log_tip "For migrating existing agents to the multiagent kit:"
        echo
        echo "  1. Add the kit as a submodule:"
        echo "     cd $WORKSPACE_DIR"
        echo "     git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit"
        echo
        echo "  2. Run the migration script:"
        echo "     ./kit/skills/multiagent-bootstrap/scripts/migrate.sh"
        echo
        echo "  Or see: kit/skills/multiagent-bootstrap/SKILL.md#migrating-existing-agents"
        echo
        exit 1
    fi
}

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."
    
    # Check for existing agents first
    if ! $DRY_RUN; then
        check_existing_agents
    fi
    
    if $DRY_RUN; then
        log_dry "Would check: openclaw CLI exists"
        log_dry "Would check: ~/.openclaw/ exists"
        log_dry "Would check: ~/.openclaw/openclaw.json exists"
        log_dry "Would check: $KIT_DIR exists"
        log_dry "Would check: $WORKSPACE_DIR/.git exists (prompt to init if not)"
        log_dry "Would check: No existing agent workspaces (migration check)"
        return 0
    fi
    
    if ! command -v openclaw &> /dev/null; then
        log_error "OpenClaw not found. Please install OpenClaw first."
        exit 1
    fi
    
    if [ ! -d "$HOME/.openclaw" ]; then
        log_error "OpenClaw config directory not found at ~/.openclaw"
        log_info "Please ensure OpenClaw is properly installed."
        exit 1
    fi
    
    if [ ! -f "$HOME/.openclaw/openclaw.json" ]; then
        log_error "OpenClaw config file not found at ~/.openclaw/openclaw.json"
        log_info "Run OpenClaw at least once to initialize the config."
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
    
    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/shared/skills"
        log_dry "Would symlink: $WORKSPACE_DIR/shared/skills/multiagent-state-manager -> $KIT_DIR/skills/multiagent-state-manager"
        log_dry "Would symlink: $WORKSPACE_DIR/shared/skills/multiagent-telegram-setup -> $KIT_DIR/skills/multiagent-telegram-setup"
        return 0
    fi
    
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
        if $DRY_RUN; then
            log_dry "Would prompt: 'What should we call your first agent?'"
            log_dry "Would default to: main"
            AGENT_NAME="main"
        else
            log_info "What should we call your first agent?"
            read -p "Agent name [main]: " AGENT_NAME
            AGENT_NAME="${AGENT_NAME:-main}"
        fi
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
    
    if $DRY_RUN; then
        log_dry "Would copy: $KIT_DIR/workspace-template -> $WORKSPACE_DIR/$AGENT_NAME"
        log_dry "Would symlink: $WORKSPACE_DIR/$AGENT_NAME/multiagent-state-manager -> ../shared/skills/multiagent-state-manager"
        log_dry "Would symlink: $WORKSPACE_DIR/$AGENT_NAME/multiagent-telegram-setup -> ../shared/skills/multiagent-telegram-setup"
        return 0
    fi
    
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
    
    if $DRY_RUN; then
        log_dry "Would prompt for: Your name"
        log_dry "Would prompt for: What agent should call you (default: your name)"
        log_dry "Would prompt for: Agent name (default: JimClaw)"
        log_dry "Would prompt for: Agent emoji (default: 🤖)"
        log_dry "Would write: $WORKSPACE_DIR/$AGENT_NAME/USER.md"
        log_dry "Would write: $WORKSPACE_DIR/$AGENT_NAME/IDENTITY.md"
        return 0
    fi
    
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

This me. I persist because someone wrote it down.
EOF
    
    log_success "Agent customized"
}

# Update OpenClaw config
update_openclaw_config() {
    log_info "Updating OpenClaw configuration..."
    
    local CONFIG_FILE="$HOME/.openclaw/openclaw.json"
    
    if $DRY_RUN; then
        log_dry "Would backup: $CONFIG_FILE"
        log_dry "Would add agent to agents.list:"
        log_dry "  { \"id\": \"$AGENT_NAME\", \"workspace\": \"$WORKSPACE_DIR/$AGENT_NAME\" }"
        return 0
    fi
    
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
    
    if $DRY_RUN; then
        log_dry "Would prompt: 'Set up Telegram for this agent now? [y/N]'"
        log_dry "Would skip by default, or run: $KIT_DIR/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py --agent $AGENT_NAME"
        return 0
    fi
    
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
    
    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/.gitignore"
        log_dry "Would run: git add -A"
        log_dry "Would run: git commit -m '[init] Bootstrap agent workspace'"
        return 0
    fi
    
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
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  OpenClaw Multi-Agent Bootstrap                        ║"
        echo "║  DRY RUN MODE - No changes will be made                ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  OpenClaw Multi-Agent Bootstrap                        ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
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
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Dry Run Complete!                                     ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  No changes were made. To run for real:                ║"
        echo "║    ./setup.sh [agent-name]                             ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Bootstrap Complete!                                   ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  Next steps:                                           ║"
        echo "║    1. Restart OpenClaw: openclaw gateway restart       ║"
        echo "║    2. Verify agent: openclaw status                    ║"
        echo "║    3. Start chatting with your agent!                  ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo
}

main
