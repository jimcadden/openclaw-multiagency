#!/bin/bash
#
# multiagency-bootstrap: One-time setup for OpenClaw multi-agent workspace
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
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

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
        log_tip "For migrating existing agents to the multiagency kit:"
        echo
        echo "  1. Add the kit as a submodule:"
        echo "     cd $WORKSPACE_DIR"
        echo "     git submodule add https://github.com/jimcadden/openclaw-multiagency.git kit"
        echo
        echo "  2. Run the migration script:"
        echo "     ./kit/skills/multiagency-bootstrap/scripts/migrate.sh"
        echo
        echo "  Or see: kit/skills/multiagency-bootstrap/SKILL.md#migrating-existing-agents"
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
    
    if [ ! -d "$OPENCLAW_DIR" ]; then
        log_error "OpenClaw config directory not found at $OPENCLAW_DIR"
        log_info "Ensure OpenClaw is installed and initialized."
        log_info "If using a custom location, pass: --openclaw-dir PATH to install.sh"
        exit 1
    fi
    
    if [ ! -f "$OPENCLAW_DIR/openclaw.json" ]; then
        log_error "openclaw.json not found in $OPENCLAW_DIR"
        log_info "Run OpenClaw at least once to initialize the config."
        exit 1
    fi
    
    if [ ! -d "$KIT_DIR" ]; then
        log_error "Kit directory not found at $KIT_DIR"
        log_info "Did you add the submodule? Run:"
        log_info "  git submodule add https://github.com/jimcadden/openclaw-multiagency.git kit"
        exit 1
    fi
    
    if [ ! -d "$WORKSPACE_DIR/.git" ]; then
        log_warn "No git repository found in $WORKSPACE_DIR"
        read -p "Initialize git repo? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            cd "$WORKSPACE_DIR"
            git init -q
            log_success "Git repo initialized"
        else
            log_error "Git is required for workspace management"
            exit 1
        fi
    fi

    # Ensure git identity is configured (may already be set by install.sh)
    local git_name git_email
    git_name=$(git -C "$WORKSPACE_DIR" config user.name 2>/dev/null || true)
    git_email=$(git -C "$WORKSPACE_DIR" config user.email 2>/dev/null || true)

    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        log_info "Git identity is needed to author commits in your workspace."

        local global_name global_email
        global_name=$(git config --global user.name 2>/dev/null || true)
        global_email=$(git config --global user.email 2>/dev/null || true)

        if [ -t 0 ]; then
            local input_name input_email
            read -p "  Git user name${global_name:+ [$global_name]}: " input_name
            input_name="${input_name:-$global_name}"
            read -p "  Git email${global_email:+ [$global_email]}: " input_email
            input_email="${input_email:-$global_email}"
        elif [ -r /dev/tty ]; then
            local input_name input_email
            printf "  Git user name%s: " "${global_name:+ [$global_name]}" >&2
            read -r input_name < /dev/tty
            input_name="${input_name:-$global_name}"
            printf "  Git email%s: " "${global_email:+ [$global_email]}" >&2
            read -r input_email < /dev/tty
            input_email="${input_email:-$global_email}"
        else
            input_name="$global_name"
            input_email="$global_email"
        fi

        [ -n "$input_name" ] && git -C "$WORKSPACE_DIR" config user.name "$input_name" && log_success "Set git user.name: $input_name"
        [ -n "$input_email" ] && git -C "$WORKSPACE_DIR" config user.email "$input_email" && log_success "Set git user.email: $input_email"

        if [ -z "$input_name" ] || [ -z "$input_email" ]; then
            log_warn "Git identity incomplete — commits may fail until configured"
        fi
    else
        log_success "Git identity: $git_name <$git_email>"
    fi

    log_success "Prerequisites OK"
}

# Create shared directory structure
setup_shared() {
    log_info "Creating shared directory structure..."
    
    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/shared/skills"
        for skill in multiagency-session multiagency-state-manager multiagency-telegram-setup multiagency-discord-setup multiagency-add-agent multiagency-remove-agent multiagency-memory-manager multiagency-thread-memory; do
            log_dry "Would symlink: $WORKSPACE_DIR/shared/skills/$skill -> $KIT_DIR/skills/$skill"
        done
        return 0
    fi
    
    mkdir -p "$WORKSPACE_DIR/shared/skills"
    
    # Symlink shared skills
    for skill in multiagency-session multiagency-state-manager multiagency-telegram-setup multiagency-discord-setup multiagency-add-agent multiagency-remove-agent multiagency-memory-manager multiagency-thread-memory; do
        if [ ! -L "$WORKSPACE_DIR/shared/skills/$skill" ]; then
            ln -s "$KIT_DIR/skills/$skill" "$WORKSPACE_DIR/shared/skills/$skill"
            log_success "Linked $skill"
        fi
    done
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
        log_dry "  (includes BOOT.md, AGENTS.md, SOUL.md, HEARTBEAT.md, MEMORY.md, USER.md, IDENTITY.md)"
        return 0
    fi
    
    cp -r "$KIT_DIR/workspace-template" "$WORKSPACE_DIR/$AGENT_NAME"
    log_success "Agent workspace created at $WORKSPACE_DIR/$AGENT_NAME"
}

# Customize agent identity
customize_agent() {
    log_info "Let's customize your agent..."
    echo
    
    if $DRY_RUN; then
        log_dry "Would prompt for: Your name"
        log_dry "Would prompt for: What agent should call you (default: your name)"
        log_dry "Would prompt for: Agent name (default: $AGENT_NAME)"
        log_dry "Would prompt for: Agent emoji (default: 🤖)"
        log_dry "Would write: $WORKSPACE_DIR/$AGENT_NAME/USER.md"
        log_dry "Would write: $WORKSPACE_DIR/$AGENT_NAME/IDENTITY.md"
        return 0
    fi
    
    # Get user info (use defaults if no terminal)
    if [ -t 0 ]; then
        read -p "Your name: " USER_NAME
        read -p "What should the agent call you? [$USER_NAME]: " USER_CALL
        read -p "Agent name (how you address it): [$AGENT_NAME] " AGENT_ID_NAME
        read -p "Agent emoji: [🤖] " AGENT_EMOJI
    elif [ -r /dev/tty ]; then
        read -p "Your name: " USER_NAME < /dev/tty
        read -p "What should the agent call you? [$USER_NAME]: " USER_CALL < /dev/tty
        read -p "Agent name (how you address it): [$AGENT_NAME] " AGENT_ID_NAME < /dev/tty
        read -p "Agent emoji: [🤖] " AGENT_EMOJI < /dev/tty
    else
        log_warn "No terminal available, using defaults"
        USER_NAME="User"
    fi
    
    # Set defaults
    USER_CALL="${USER_CALL:-$USER_NAME}"
    AGENT_ID_NAME="${AGENT_ID_NAME:-$AGENT_NAME}"
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
    
    local CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
    
    if $DRY_RUN; then
        log_dry "Would backup: $CONFIG_FILE"
        log_dry "Would add agent to agents.list:"
        log_dry "  { \"id\": \"$AGENT_NAME\", \"workspace\": \"$WORKSPACE_DIR/$AGENT_NAME\" }"
        log_dry "Would set skills.load.extraDirs: [\"$WORKSPACE_DIR/shared/skills\"]"
        log_dry "Would set session.idleMinutes: 10080 (7 days, if not already set)"
        return 0
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "openclaw.json not found at $CONFIG_FILE"
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
shared_skills = "$WORKSPACE_DIR/shared/skills"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    # ── agents.list ──────────────────────────────────────────────────────────
    if 'agents' not in config:
        config['agents'] = {}
    if 'list' not in config['agents']:
        config['agents']['list'] = []

    existing = [a for a in config['agents']['list'] if a.get('id') == agent_id]
    if not existing:
        config['agents']['list'].append({'id': agent_id, 'workspace': workspace})
        print(f"Added agent '{agent_id}' to agents.list")
    else:
        print(f"Agent '{agent_id}' already in agents.list")

    # ── skills.load.extraDirs ────────────────────────────────────────────────
    if 'skills' not in config:
        config['skills'] = {}
    if 'load' not in config['skills']:
        config['skills']['load'] = {}
    extra_dirs = config['skills']['load'].get('extraDirs', [])
    if shared_skills not in extra_dirs:
        extra_dirs.append(shared_skills)
        config['skills']['load']['extraDirs'] = extra_dirs
        print(f"Added '{shared_skills}' to skills.load.extraDirs")
    else:
        print(f"skills.load.extraDirs already contains shared/skills")

    # ── session.idleMinutes ──────────────────────────────────────────────────
    if 'session' not in config:
        config['session'] = {}
    if 'idleMinutes' not in config['session']:
        config['session']['idleMinutes'] = 10080
        print("Set session.idleMinutes to 10080 (7 days, default)")
    else:
        print(f"session.idleMinutes already set: {config['session']['idleMinutes']}")

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

except Exception as e:
    print(f"Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    log_success "OpenClaw config updated"
}

# Prompt for Telegram setup
prompt_telegram() {
    echo
    if $DRY_RUN; then
        log_dry "Would prompt: 'Set up Telegram for this agent now? [y/N]'"
        return 0
    fi
    
    log_info "Telegram Setup"
    log_info "--------------"

    local reply=""
    if [ -t 0 ]; then
        read -p "Set up Telegram for this agent now? [y/N] " -n 1 -r reply
        echo
    elif [ -r /dev/tty ]; then
        printf "Set up Telegram for this agent now? [y/N] " >&2
        read -r reply < /dev/tty
    fi

    if [[ "$reply" =~ ^[Yy]$ ]]; then
        log_info "Running Telegram setup..."
        if [ -f "$KIT_DIR/skills/multiagency-telegram-setup/scripts/setup-telegram-agent.sh" ]; then
            bash "$KIT_DIR/skills/multiagency-telegram-setup/scripts/setup-telegram-agent.sh" --agent "$AGENT_NAME"
        else
            log_warn "Telegram setup script not found"
        fi
    else
        log_info "Skipped. Run later with:"
        log_info "  $KIT_DIR/skills/multiagency-telegram-setup/scripts/setup-telegram-agent.sh --agent $AGENT_NAME"
    fi
}

# Prompt for Discord setup
prompt_discord() {
    echo
    if $DRY_RUN; then
        log_dry "Would prompt: 'Set up Discord for this agent now? [y/N]'"
        return 0
    fi
    
    log_info "Discord Setup"
    log_info "-------------"

    local reply=""
    if [ -t 0 ]; then
        read -p "Set up Discord for this agent now? [y/N] " -n 1 -r reply
        echo
    elif [ -r /dev/tty ]; then
        printf "Set up Discord for this agent now? [y/N] " >&2
        read -r reply < /dev/tty
    fi

    if [[ "$reply" =~ ^[Yy]$ ]]; then
        log_info "Running Discord setup..."
        if [ -f "$KIT_DIR/skills/multiagency-discord-setup/scripts/setup-discord-agent.sh" ]; then
            bash "$KIT_DIR/skills/multiagency-discord-setup/scripts/setup-discord-agent.sh" --agent "$AGENT_NAME"
        else
            log_warn "Discord setup script not found"
        fi
    else
        log_info "Skipped. Run later with:"
        log_info "  $KIT_DIR/skills/multiagency-discord-setup/scripts/setup-discord-agent.sh --agent $AGENT_NAME"
    fi
}

# Gateway restart
restart_gateway() {
    if $DRY_RUN; then
        log_dry "Would restart OpenClaw gateway to load new skills"
        return 0
    fi

    if ! command -v openclaw &> /dev/null; then
        log_warn "openclaw CLI not found — restart the gateway manually:"
        log_info "  openclaw gateway restart"
        return 0
    fi

    log_info "Restarting OpenClaw gateway to load multiagency skills..."
    if openclaw gateway restart 2>/dev/null; then
        log_success "Gateway restarted — multiagency skills are now available"
    else
        log_warn "Gateway restart failed — restart manually:"
        log_info "  openclaw gateway restart"
    fi
}

# Initial git commit
git_commit() {
    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/.gitignore"
        log_dry "Would prompt: Create initial git commit? [Y/n]"
        log_dry "Would run: git add -A && git commit -m '[init] Bootstrap agent workspace'"
        return 0
    fi

    cd "$WORKSPACE_DIR"

    # Always create .gitignore so it's ready even if the commit is skipped
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

    echo
    log_info "Git Commit"
    log_info "----------"

    local reply=""
    if [ -t 0 ]; then
        read -p "Create initial git commit? [Y/n] " -n 1 -r reply
        echo
    elif [ -r /dev/tty ]; then
        printf "Create initial git commit? [Y/n] " >&2
        read -r reply < /dev/tty
    fi

    # Default to yes
    if [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]; then
        # Identity should have been configured in check_prereqs; verify as a safety net
        local git_name git_email
        git_name=$(git -C "$WORKSPACE_DIR" config user.name 2>/dev/null || true)
        git_email=$(git -C "$WORKSPACE_DIR" config user.email 2>/dev/null || true)

        if [ -z "$git_name" ] || [ -z "$git_email" ]; then
            log_warn "Git identity not configured — cannot commit."
            log_info "  git -C $WORKSPACE_DIR config user.name \"Your Name\""
            log_info "  git -C $WORKSPACE_DIR config user.email \"you@example.com\""
            return 0
        fi

        git add -A
        git commit -m "[init] Bootstrap agent workspace

Agent: $AGENT_NAME
OpenClaw: $(openclaw version 2>/dev/null || echo 'unknown')"
        log_success "Initial commit created"
    else
        log_info "Skipped. Commit manually when ready:"
        log_info "  cd $WORKSPACE_DIR && git add -A && git commit -m '[init] Bootstrap agent workspace'"
    fi
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
    prompt_discord
    git_commit
    restart_gateway
    
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
        echo "║    1. Verify agent: openclaw status                    ║"
        echo "║    2. Start chatting!                                  ║"
        echo "║                                                        ║"
        echo "║  Add more agents:                                      ║"
        echo "║    ./kit/scripts/add-agent.sh [agent-name]             ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo
}

main
