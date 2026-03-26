#!/bin/bash
#
# migrate.sh: Migrate existing OpenClaw agents to use the multiagent kit
#
# Usage: ./migrate.sh [--dry-run]
#
# This script is for users who already have agents set up and want to
# start using the openclaw-multiagent kit without losing their data.
#

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

for arg in "$@"; do
    case $arg in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
    esac
done

# Paths
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspaces}"
KIT_DIR="${KIT_DIR:-$WORKSPACE_DIR/kit}"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_tip() { echo -e "${CYAN}💡${NC} $1"; }
log_dry() { echo -e "${CYAN}[DRY RUN]${NC} $1"; }

# Find all agent directories
find_agents() {
    local agents=()
    for dir in "$WORKSPACE_DIR"/*/; do
        if [ -d "$dir" ] && [ -f "$dir/IDENTITY.md" ] && [ -f "$dir/SOUL.md" ]; then
            agents+=("$(basename "$dir")")
        fi
    done
    echo "${agents[@]}"
}

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."
    
    if $DRY_RUN; then
        log_dry "Would check: Git repo initialized in $WORKSPACE_DIR"
        log_dry "Would check: Kit directory exists at $KIT_DIR (or prompt to add submodule)"
        return 0
    fi
    
    if [ ! -d "$WORKSPACE_DIR/.git" ]; then
        log_error "No git repository found in $WORKSPACE_DIR"
        log_info "Please initialize a git repo first: cd $WORKSPACE_DIR && git init"
        exit 1
    fi
    
    if [ ! -d "$KIT_DIR" ]; then
        log_warn "Kit directory not found at $KIT_DIR"
        log_info "Adding the kit as a submodule..."
        cd "$WORKSPACE_DIR"
        git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit
        log_success "Submodule added"
    fi
    
    log_success "Prerequisites OK"
}

# Setup agent symlinks
setup_agent_symlinks() {
    local agent_name="$1"
    local agent_dir="$WORKSPACE_DIR/$agent_name"
    
    log_info "Setting up agent: $agent_name"
    
    if $DRY_RUN; then
        log_dry "Would clean up old symlinks in $agent_dir (if exist)"
        log_dry "Would create/replace symlinks:"
        log_dry "  - multiagent-state-manager -> ../kit/skills/multiagent-state-manager"
        log_dry "  - multiagent-telegram-setup -> ../kit/skills/multiagent-telegram-setup"
        return 0
    fi
    
    cd "$agent_dir"
    
    # Clean up old symlinks (from early dev versions)
    if [ -L "agent-state-manager" ]; then
        rm -f agent-state-manager
        log_success "Removed old symlink: agent-state-manager"
    fi
    
    if [ -L "telegram-agent-setup" ]; then
        rm -f telegram-agent-setup
        log_success "Removed old symlink: telegram-agent-setup"
    fi
    
    # Remove any existing new symlinks (clean slate)
    if [ -L "multiagent-state-manager" ]; then
        rm -f multiagent-state-manager
    fi
    
    if [ -L "multiagent-telegram-setup" ]; then
        rm -f multiagent-telegram-setup
    fi
    
    # Create new symlinks
    ln -s "../kit/skills/multiagent-state-manager" multiagent-state-manager
    ln -s "../kit/skills/multiagent-telegram-setup" multiagent-telegram-setup
    
    log_success "Symlinks created for $agent_name"
}

# Setup shared skills directory
setup_shared_skills() {
    log_info "Setting up shared skills..."
    
    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/shared/skills/"
        log_dry "Would clean up old symlinks (if exist)"
        log_dry "Would create symlinks:"
        log_dry "  - multiagent-state-manager -> ../../kit/skills/multiagent-state-manager"
        log_dry "  - multiagent-telegram-setup -> ../../kit/skills/multiagent-telegram-setup"
        return 0
    fi
    
    mkdir -p "$WORKSPACE_DIR/shared/skills"
    cd "$WORKSPACE_DIR/shared/skills"
    
    # Clean up old symlinks (from early dev versions)
    if [ -L "agent-state-manager" ]; then
        rm -f agent-state-manager
        log_success "Removed old symlink: agent-state-manager"
    fi
    
    if [ -L "telegram-agent-setup" ]; then
        rm -f telegram-agent-setup
        log_success "Removed old symlink: telegram-agent-setup"
    fi
    
    # Remove any existing new symlinks (clean slate)
    if [ -L "multiagent-state-manager" ]; then
        rm -f multiagent-state-manager
    fi
    
    if [ -L "multiagent-telegram-setup" ]; then
        rm -f multiagent-telegram-setup
    fi
    
    # Create symlinks
    ln -s "../../kit/skills/multiagent-state-manager" multiagent-state-manager
    ln -s "../../kit/skills/multiagent-telegram-setup" multiagent-telegram-setup
    
    log_success "Shared skills configured"
}

# Commit changes
git_commit() {
    log_info "Committing changes..."
    
    if $DRY_RUN; then
        log_dry "Would run: git add kit (if submodule was added)"
        log_dry "Would run: git add -A (for all symlink changes)"
        log_dry "Would run: git commit -m '[main] Add openclaw-multiagent kit'"
        return 0
    fi
    
    cd "$WORKSPACE_DIR"
    
    # Stage the submodule if it was just added
    if [ -d "kit/.git" ]; then
        git add kit
    fi
    
    # Stage all changes
    git add -A
    
    # Commit if there are changes
    if git diff --cached --quiet; then
        log_warn "No changes to commit"
    else
        git commit -m "[main] Add openclaw-multiagent kit

- Added openclaw-multiagent as submodule
- Created shared/skills/ with kit symlinks
- Added skill symlinks to all agents"
        log_success "Changes committed"
    fi
}

# Main
main() {
    echo
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  OpenClaw Multi-Agent Migration                        ║"
        echo "║  DRY RUN MODE - No changes will be made                ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  OpenClaw Multi-Agent Migration                        ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo
    
    check_prereqs
    
    # Find agents
    local agents
    agents=$(find_agents)
    
    if [ -z "$agents" ]; then
        log_error "No existing agents found in $WORKSPACE_DIR"
        log_info "If this is a fresh install, use setup.sh instead:"
        log_tip "  ./kit/skills/multiagent-bootstrap/scripts/setup.sh"
        exit 1
    fi
    
    log_info "Found agents: $agents"
    echo
    
    # Setup shared skills
    setup_shared_skills
    echo
    
    # Setup each agent
    for agent in $agents; do
        setup_agent_symlinks "$agent"
        echo
    done
    
    # Commit
    git_commit
    
    echo
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Dry Run Complete!                                     ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  No changes were made. To run for real:                ║"
        echo "║    ./migrate.sh                                        ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Migration Complete!                                   ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  Next steps:                                           ║"
        echo "║    1. Review the changes: git show HEAD                ║"
        echo "║    2. Push to remote: git push origin main             ║"
        echo "║    3. Restart OpenClaw: openclaw gateway restart       ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo
}

main
