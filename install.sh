#!/bin/bash
#
# Install OpenClaw Multi-Agent Kit
# 
# Quick install: curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagency/main/install.sh | bash

set -e

# Check if we can run interactively
if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    echo "Error: This script requires an interactive terminal." >&2
    echo "Run with: bash install.sh (not piped)" >&2
    echo "Or use: ./install.sh --workspace DIR --agent NAME" >&2
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
KIT_REPO="https://github.com/jimcadden/openclaw-multiagency.git"
WORKSPACE_DIR=""
AGENT_NAME=""
OPENCLAW_DIR=""

# Input helper - reads from terminal even when piped
read_tty() {
    local prompt="$1"
    local default="${2:-}"
    local input=""
    
    # Print prompt to stderr (visible even when piping)
    printf "%s" "$prompt" >&2
    
    if [ -t 0 ]; then
        # stdin is terminal - read normally
        IFS= read -r input
    elif [ -r /dev/tty ]; then
        # Read from tty
        IFS= read -r input < /dev/tty
    else
        # Fallback - empty
        input=""
    fi
    
    # Trim trailing newline
    input="${input%$'\n'}"
    
    # Use default if empty
    if [ -z "$input" ] && [ -n "$default" ]; then
        input="$default"
    fi
    
    printf "%s" "$input"
}

# Yes/no prompt helper
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local input
    local yn="[y/N]"
    
    if [ "$default" = "y" ]; then
        yn="[Y/n]"
    fi
    
    input=$(read_tty "$prompt $yn " "")
    
    if [ -z "$input" ]; then
        input="$default"
    fi
    
    [[ "$input" =~ ^[Yy]$ ]]
}

# Logging helpers
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo; echo -e "${CYAN}▶ $1${NC}"; }

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --workspace|-w)
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    log_error "--workspace requires a directory path"
                    exit 1
                fi
                WORKSPACE_DIR="$2"
                shift 2
                ;;
            --agent|-a)
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    log_error "--agent requires a name"
                    exit 1
                fi
                AGENT_NAME="$2"
                shift 2
                ;;
            --openclaw-dir|-c)
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    log_error "--openclaw-dir requires a directory path"
                    exit 1
                fi
                OPENCLAW_DIR="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo "OpenClaw Multi-Agent Kit Installer"
    echo ""
    echo "Usage: install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -w, --workspace DIR      Workspace directory (default: ~/workspaces)"
    echo "  -a, --agent NAME         First agent name (default: main)"
    echo "  -c, --openclaw-dir DIR   OpenClaw config directory (default: ~/.openclaw)"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Requirements:"
    echo "  OpenClaw must be installed and initialized before running this script."
    echo "  The OpenClaw config directory must contain openclaw.json."
    echo ""
    echo "Examples:"
    echo '  curl -fsSL .../install.sh | bash'
    echo '  curl -fsSL .../install.sh | bash -s -- --agent bot --workspace ~/agents'
    echo '  bash install.sh --openclaw-dir /custom/oc --workspace ~/agents --agent main'
}

# Get workspace directory
get_workspace_dir() {
    if [ -z "$WORKSPACE_DIR" ]; then
        log_step "Workspace Setup"
        local input
        input=$(read_tty "Enter workspace directory [~/workspaces]: " "~/workspaces")
        WORKSPACE_DIR="${input/#\~/$HOME}"
    fi
    
    # Expand tilde
    WORKSPACE_DIR="${WORKSPACE_DIR/#\~/$HOME}"
    
    log_info "Using workspace: $WORKSPACE_DIR"
}

# Get agent name
get_agent_name() {
    if [ -z "$AGENT_NAME" ]; then
        log_step "Agent Configuration"
        local input
        input=$(read_tty "What should we call your first agent? [main]: " "main")
        AGENT_NAME="$input"
    fi
    
    log_info "Agent name: $AGENT_NAME"
}

# Ask about Telegram (handled by bootstrap script)
# Bootstrap has its own prompt_telegram function that asks interactively
ask_telegram() {
    # Bootstrap will handle Telegram setup at the end
    : 
}

# Resolve and validate the OpenClaw config directory
resolve_openclaw_dir() {
    # Expand tilde if present
    OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
    OPENCLAW_DIR="${OPENCLAW_DIR/#\~/$HOME}"
}

# Check prerequisites
check_prereqs() {
    log_step "Prerequisites"
    
    if ! command -v git &> /dev/null; then
        log_error "git is required but not installed."
        exit 1
    fi
    log_success "git found"

    if ! command -v python3 &> /dev/null; then
        log_error "python3 is required but not found on PATH."
        log_info "Install Python 3 and ensure it is on your PATH, then re-run."
        exit 1
    fi
    log_success "python3 found"

    if [ ! -d "$OPENCLAW_DIR" ]; then
        log_error "OpenClaw config directory not found: $OPENCLAW_DIR"
        log_info "Ensure OpenClaw is installed and initialized."
        log_info "If using a custom location, pass: --openclaw-dir PATH"
        exit 1
    fi
    log_success "OpenClaw config directory found: $OPENCLAW_DIR"

    if [ ! -f "$OPENCLAW_DIR/openclaw.json" ]; then
        log_error "openclaw.json not found in $OPENCLAW_DIR"
        log_info "Run OpenClaw at least once to generate the config, then re-run."
        exit 1
    fi
    log_success "openclaw.json found"
    
    log_success "All prerequisites met"
}

# Set up git repository and identity for workspace commits
setup_git() {
    log_step "Git Setup"

    mkdir -p "$WORKSPACE_DIR"

    if [ -d "$WORKSPACE_DIR/.git" ]; then
        log_success "Existing git repository found: $WORKSPACE_DIR"
        if ! confirm "Use this repository for workspace management?" "y"; then
            log_info "Aborted — a git repository is required for workspace management"
            exit 0
        fi
    else
        log_info "No git repository in $WORKSPACE_DIR"
        if confirm "Initialize a git repository to manage your workspaces?" "y"; then
            git -C "$WORKSPACE_DIR" init -q
            log_success "Initialized git repository"
        else
            log_warn "Skipping git init — you can initialize manually later:"
            log_info "  cd $WORKSPACE_DIR && git init"
            return 0
        fi
    fi

    # Check git identity (local repo config, then global fallback)
    local git_name git_email
    git_name=$(git -C "$WORKSPACE_DIR" config user.name 2>/dev/null || true)
    git_email=$(git -C "$WORKSPACE_DIR" config user.email 2>/dev/null || true)

    if [ -n "$git_name" ] && [ -n "$git_email" ]; then
        log_success "Git identity: $git_name <$git_email>"
        return 0
    fi

    log_info "Git identity is needed to author commits in your workspace."

    local global_name global_email
    global_name=$(git config --global user.name 2>/dev/null || true)
    global_email=$(git config --global user.email 2>/dev/null || true)

    local input_name input_email
    if [ -n "$global_name" ]; then
        input_name=$(read_tty "  Git user name [$global_name]: " "$global_name")
    else
        input_name=$(read_tty "  Git user name: " "")
    fi
    if [ -n "$global_email" ]; then
        input_email=$(read_tty "  Git email [$global_email]: " "$global_email")
    else
        input_email=$(read_tty "  Git email: " "")
    fi

    if [ -n "$input_name" ]; then
        git -C "$WORKSPACE_DIR" config user.name "$input_name"
        log_success "Set git user.name: $input_name"
    fi
    if [ -n "$input_email" ]; then
        git -C "$WORKSPACE_DIR" config user.email "$input_email"
        log_success "Set git user.email: $input_email"
    fi

    if [ -z "$input_name" ] || [ -z "$input_email" ]; then
        log_warn "Git identity incomplete — commits may fail until configured"
        log_info "  git -C $WORKSPACE_DIR config user.name \"Your Name\""
        log_info "  git -C $WORKSPACE_DIR config user.email \"you@example.com\""
    fi
}

# Setup the kit
setup_kit() {
    log_step "Installing Multi-Agent Kit"
    
    mkdir -p "$WORKSPACE_DIR"
    cd "$WORKSPACE_DIR"
    
    # Init git if it wasn't set up earlier (e.g., user skipped setup_git)
    if [ ! -d ".git" ]; then
        git init -q
        log_success "Initialized git repository"
    fi
    
    # Add kit as submodule
    if [ ! -d "kit" ]; then
        log_info "Cloning kit..."
        git submodule add -q "$KIT_REPO" kit
        log_success "Added kit"
    fi
    
    # Checkout latest stable tag
    cd kit
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$LATEST_TAG" ]; then
        git checkout "$LATEST_TAG" 2>/dev/null
        log_success "Kit version: $LATEST_TAG"
    fi
    cd ..
    
    # Write version file for agent boot sequence
    local kit_version="${LATEST_TAG:-$(git -C kit rev-parse --short HEAD)}"
    echo "$kit_version" > .kit-version
    
    export WORKSPACE_DIR
    export KIT_DIR="$WORKSPACE_DIR/kit"
    export OPENCLAW_DIR
}

# Run bootstrap
run_bootstrap() {
    log_step "Creating Agent"
    
    if [ -f "$WORKSPACE_DIR/kit/skills/multiagency-bootstrap/scripts/setup.sh" ]; then
        "$WORKSPACE_DIR/kit/skills/multiagency-bootstrap/scripts/setup.sh" "$AGENT_NAME"
    else
        log_error "Bootstrap script not found"
        exit 1
    fi
}

# Main
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  OpenClaw Multi-Agent Kit Install                     ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo
    
    parse_args "$@"
    resolve_openclaw_dir
    check_prereqs
    get_workspace_dir
    get_agent_name
    ask_telegram
    
    # Confirm everything
    log_step "Ready to Install"
    log_info "OpenClaw config: $OPENCLAW_DIR"
    log_info "Workspace: $WORKSPACE_DIR"
    log_info "Agent: $AGENT_NAME"
    
    if ! confirm "Continue?" "y"; then
        log_info "Aborted"
        exit 0
    fi
    
    setup_git
    setup_kit
    run_bootstrap
    
    echo
    log_success "Installation complete!"
    log_info "Agent workspace: $WORKSPACE_DIR/$AGENT_NAME"
}

main "$@"
