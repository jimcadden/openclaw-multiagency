#!/bin/bash
#
# migrate.sh: Migrate existing OpenClaw agents to the multiagency kit
#
# For users who already have agents set up and want to add the
# openclaw-multiagency kit without losing any existing agent data.
#
# Usage:
#   ./migrate.sh [OPTIONS]
#   ./migrate.sh --dry-run
#
# Options:
#   -w, --workspace DIR      Workspace directory (default: ~/.openclaw/workspace)
#   -c, --openclaw-dir DIR   OpenClaw config directory (default: ~/.openclaw)
#   -n, --dry-run            Preview changes without making them
#   -h, --help               Show this help

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
log_tip()     { echo -e "${CYAN}💡${NC} $1"; }
log_dry()     { echo -e "${CYAN}[DRY RUN]${NC} $1"; }
log_step()    { echo; echo -e "${CYAN}▶ $1${NC}"; }

# ─── Defaults ─────────────────────────────────────────────────────────────────

KIT_REPO="https://github.com/jimcadden/openclaw-multiagency.git"
WORKSPACE_DIR="${WORKSPACE_DIR:-}"
OPENCLAW_DIR="${OPENCLAW_DIR:-}"
DRY_RUN=false

# ─── Argument parsing ─────────────────────────────────────────────────────────

show_help() {
    echo "OpenClaw Multi-Agent Kit — Migration Script"
    echo ""
    echo "Migrates existing OpenClaw agents to use the multiagency kit."
    echo "Preserves all existing agent data (IDENTITY.md, MEMORY.md, etc.)."
    echo ""
    echo "Usage: migrate.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -w, --workspace DIR      Workspace directory (default: ~/.openclaw/workspace)"
    echo "  -c, --openclaw-dir DIR   OpenClaw config directory (default: ~/.openclaw)"
    echo "  -n, --dry-run            Preview changes without making them"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Requirements:"
    echo "  OpenClaw must be installed and initialized (openclaw.json must exist)."
    echo "  Workspace must be a git repository containing existing agent directories."
    echo ""
    echo "Examples:"
    echo "  ./migrate.sh"
    echo "  ./migrate.sh --dry-run"
    echo "  ./migrate.sh --workspace ~/agents --openclaw-dir /custom/oc"
}

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
            --openclaw-dir|-c)
                if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
                    log_error "--openclaw-dir requires a directory path"
                    exit 1
                fi
                OPENCLAW_DIR="$2"
                shift 2
                ;;
            --dry-run|-n)
                DRY_RUN=true
                shift
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

# ─── Resolve paths ────────────────────────────────────────────────────────────

resolve_paths() {
    # Apply defaults and expand tildes
    OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
    OPENCLAW_DIR="${OPENCLAW_DIR/#\~/$HOME}"

    # If workspace not set by flag/env, try to infer from script location first.
    # migrate.sh lives at: <workspace>/kit/skills/multiagency-bootstrap/scripts/migrate.sh
    # Five parent dirs up = workspace.
    if [ -z "$WORKSPACE_DIR" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local auto_workspace
        auto_workspace="$(dirname "$(dirname "$(dirname "$(dirname "$script_dir")")")")"
        # Validate: parent of auto-detected path should contain a kit/ subdir
        if [ -d "$auto_workspace/kit" ]; then
            WORKSPACE_DIR="$auto_workspace"
        else
            WORKSPACE_DIR="$HOME/.openclaw/workspace"
        fi
    fi

    WORKSPACE_DIR="${WORKSPACE_DIR/#\~/$HOME}"
    KIT_DIR="$WORKSPACE_DIR/kit"
}

# ─── Prerequisites ────────────────────────────────────────────────────────────

check_prereqs() {
    log_step "Prerequisites"

    if $DRY_RUN; then
        log_dry "Would check: git on PATH"
        log_dry "Would check: python3 on PATH"
        log_dry "Would check: $OPENCLAW_DIR exists"
        log_dry "Would check: $OPENCLAW_DIR/openclaw.json exists"
        log_dry "Would check: $WORKSPACE_DIR/.git exists"
        return 0
    fi

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

    if [ ! -d "$WORKSPACE_DIR" ]; then
        log_error "Workspace directory not found: $WORKSPACE_DIR"
        log_info "If your workspace is in a different location, pass: --workspace PATH"
        exit 1
    fi
    log_success "Workspace directory found: $WORKSPACE_DIR"

    log_success "All prerequisites met"
}

# ─── Input helper ─────────────────────────────────────────────────────────────

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

    input="${input%$'\n'}"
    if [ -z "$input" ] && [ -n "$default" ]; then
        input="$default"
    fi

    printf "%s" "$input"
}

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

# ─── Git setup ────────────────────────────────────────────────────────────────

setup_git() {
    log_step "Git Setup"

    if $DRY_RUN; then
        if [ -d "$WORKSPACE_DIR/.git" ]; then
            log_dry "Would confirm: Use existing git repository at $WORKSPACE_DIR"
        else
            log_dry "Would prompt: Initialize a git repository in $WORKSPACE_DIR"
        fi
        log_dry "Would check/prompt for git user identity (user.name, user.email)"
        return 0
    fi

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
            log_error "Git repository is required. Initialize manually:"
            log_info "  cd $WORKSPACE_DIR && git init"
            exit 1
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

# ─── Layout detection ─────────────────────────────────────────────────────────

# Returns "flat" if agent files are at workspace root, "multiagency" if in subdirs,
# or "none" if no agents found.
# Note: callers should also accept "multiagent" (legacy) as equivalent to "multiagency".
detect_layout() {
    # Check flat: workspace root itself is the agent
    if [ -f "$WORKSPACE_DIR/IDENTITY.md" ] && [ -f "$WORKSPACE_DIR/SOUL.md" ]; then
        echo "flat"
        return
    fi

    # Check multiagency: agent subdirs present
    for dir in "$WORKSPACE_DIR"/*/; do
        local name
        name="$(basename "$dir")"
        [ "$name" = "kit" ] || [ "$name" = "shared" ] && continue
        if [ -d "$dir" ] && [ -f "${dir}IDENTITY.md" ] && [ -f "${dir}SOUL.md" ]; then
            echo "multiagency"
            return
        fi
    done

    echo "none"
}

# ─── Find existing agents ─────────────────────────────────────────────────────

find_agents() {
    local agents=()
    for dir in "$WORKSPACE_DIR"/*/; do
        local name
        name="$(basename "$dir")"
        [ "$name" = "kit" ] || [ "$name" = "shared" ] && continue
        if [ -d "$dir" ] && [ -f "${dir}IDENTITY.md" ] && [ -f "${dir}SOUL.md" ]; then
            agents+=("$name")
        fi
    done
    echo "${agents[@]:-}"
}

# ─── Flat workspace restructure ───────────────────────────────────────────────

restructure_flat_workspace() {
    log_step "Restructuring Flat Workspace"
    log_info "Detected single-agent layout: agent files are at workspace root."
    log_info "Migration requires a multiagency layout: agent files in a named subdirectory."
    echo

    # Prompt for agent name (use default in dry-run)
    local agent_name=""
    if $DRY_RUN; then
        agent_name="main"
    elif [ -t 0 ]; then
        read -p "Agent directory name [main]: " agent_name
    elif [ -r /dev/tty ]; then
        printf "Agent directory name [main]: " >&2
        read -r agent_name < /dev/tty
    fi
    agent_name="${agent_name:-main}"

    if [[ ! "$agent_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Agent name must be alphanumeric (hyphens/underscores OK)"
        exit 1
    fi

    local target_dir="$WORKSPACE_DIR/$agent_name"
    if [ -d "$target_dir" ]; then
        log_error "Directory '$target_dir' already exists — cannot restructure"
        exit 1
    fi

    # Show what will move
    log_info "Files to move into $target_dir/:"
    local files_to_move=()
    for item in "$WORKSPACE_DIR"/*; do
        local base
        base="$(basename "$item")"
        case "$base" in
            kit|shared|.git|.gitmodules|.gitignore|.gitattributes) continue ;;
        esac
        echo "    $base"
        files_to_move+=("$base")
    done
    echo

    if $DRY_RUN; then
        log_dry "Would create: $target_dir"
        for f in "${files_to_move[@]}"; do
            log_dry "Would move:   $f -> $agent_name/$f"
        done
        # Set so rest of dry-run uses the new agent name
        RESTRUCTURED_AGENT="$agent_name"
        return 0
    fi

    local reply=""
    if [ -t 0 ]; then
        read -p "Proceed with restructuring? [Y/n] " -n 1 -r reply
        echo
    elif [ -r /dev/tty ]; then
        printf "Proceed with restructuring? [Y/n] " >&2
        read -r reply < /dev/tty
    fi

    if [[ -n "$reply" && ! "$reply" =~ ^[Yy]$ ]]; then
        log_info "Aborted"
        exit 0
    fi

    mkdir -p "$target_dir"

    # Use git mv to preserve history if possible, fall back to mv
    local use_git_mv=false
    if [ -d "$WORKSPACE_DIR/.git" ]; then
        use_git_mv=true
    fi

    cd "$WORKSPACE_DIR"
    for f in "${files_to_move[@]}"; do
        if $use_git_mv && git ls-files --error-unmatch "$f" &>/dev/null 2>&1; then
            git mv "$f" "$agent_name/"
        else
            mv "$f" "$target_dir/"
        fi
        log_success "Moved: $f -> $agent_name/$f"
    done

    RESTRUCTURED_AGENT="$agent_name"
    log_success "Workspace restructured — agent is now at $target_dir"
}

# ─── Update agent in openclaw.json ────────────────────────────────────────────

register_agent_in_config() {
    local agent_name="$1"
    local agent_workspace="$WORKSPACE_DIR/$agent_name"
    local config_file="$OPENCLAW_DIR/openclaw.json"

    [ -f "$config_file" ] || return 0

    python3 << EOF
import json, sys

config_file = "$config_file"
agent_id = "$agent_name"
workspace = "$agent_workspace"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    if 'agents' not in config:
        config['agents'] = {}
    if 'list' not in config['agents']:
        config['agents']['list'] = []

    existing = [a for a in config['agents']['list'] if a.get('id') == agent_id]
    if not existing:
        config['agents']['list'].append({'id': agent_id, 'workspace': workspace})
        print(f"Registered agent '{agent_id}' in openclaw.json (workspace: {workspace})")
    else:
        print(f"Agent '{agent_id}' already in openclaw.json")

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
except Exception as e:
    print(f"Warning: could not update openclaw.json: {e}", file=sys.stderr)
EOF
}

# ─── Kit setup ────────────────────────────────────────────────────────────────

setup_kit() {
    log_step "Kit Setup"

    if $DRY_RUN; then
        if [ -d "$KIT_DIR" ]; then
            log_dry "Kit already present at $KIT_DIR — would verify tag"
        else
            log_dry "Would add submodule: $KIT_REPO -> $KIT_DIR"
            log_dry "Would checkout latest stable tag"
        fi
        return 0
    fi

    cd "$WORKSPACE_DIR"

    if [ ! -d "$KIT_DIR" ]; then
        log_info "Adding kit submodule..."
        git submodule add -q "$KIT_REPO" kit
        log_success "Kit added"
    else
        log_info "Kit already present at $KIT_DIR"
        # Ensure submodule is initialized if it exists as a directory but not registered
        git submodule update --init --recursive kit 2>/dev/null || true
    fi

    # Checkout latest stable tag
    cd "$KIT_DIR"
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$LATEST_TAG" ]; then
        git checkout "$LATEST_TAG" -q 2>/dev/null
        log_success "Kit version: $LATEST_TAG"
    else
        log_warn "No release tags found — using current HEAD"
    fi
    cd "$WORKSPACE_DIR"

    # Write version file for agent boot sequence
    local kit_version="${LATEST_TAG:-$(git -C "$KIT_DIR" rev-parse --short HEAD)}"
    echo "$kit_version" > .kit-version
    log_success "Wrote .kit-version ($kit_version)"
}

# ─── Shared skills ────────────────────────────────────────────────────────────

setup_shared_skills() {
    log_step "Shared Skills"

    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/shared/skills/"
        for skill in multiagency-session multiagency-state-manager multiagency-telegram-setup multiagency-add-agent multiagency-remove-agent multiagency-memory-manager multiagency-thread-memory; do
            log_dry "Would symlink: shared/skills/$skill -> ../../kit/skills/$skill"
        done
        return 0
    fi

    mkdir -p "$WORKSPACE_DIR/shared/skills"
    cd "$WORKSPACE_DIR/shared/skills"

    # Remove old-name symlinks from early dev versions
    for old in agent-state-manager telegram-agent-setup multiagency-kit-guide; do
        [ -L "$old" ] && rm -f "$old" && log_success "Removed legacy symlink: $old"
    done

    # Remove and recreate to ensure correct target
    for skill in multiagency-session multiagency-state-manager multiagency-telegram-setup multiagency-add-agent multiagency-remove-agent multiagency-memory-manager multiagency-thread-memory; do
        [ -L "$skill" ] && rm -f "$skill"
        ln -s "../../kit/skills/$skill" "$skill"
        log_success "Linked shared/skills/$skill"
    done

    cd "$WORKSPACE_DIR"
}

# ─── Per-agent symlinks ───────────────────────────────────────────────────────

setup_agent_symlinks() {
    local agent_name="$1"
    local agent_dir="$WORKSPACE_DIR/$agent_name"

    log_info "Wiring agent: $agent_name"

    if $DRY_RUN; then
        log_dry "  Would remove legacy symlinks from $agent_dir (if present)"
        return 0
    fi

    cd "$agent_dir"

    # Remove all legacy per-agent skill symlinks (old names and current names)
    # Skills are now discovered via skills.load.extraDirs in openclaw.json
    for link in agent-state-manager telegram-agent-setup \
                multiagency-state-manager multiagency-telegram-setup multiagency-kit-guide \
                multiagency-add-agent; do
        if [ -L "$link" ]; then
            rm -f "$link"
            log_success "  Removed legacy symlink: $link"
        fi
    done

    cd "$WORKSPACE_DIR"
}

# ─── OpenClaw config: skills.load.extraDirs ──────────────────────────────────

update_skills_config() {
    local CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
    local SHARED_SKILLS="$WORKSPACE_DIR/shared/skills"

    log_step "Skills Config"

    if $DRY_RUN; then
        log_dry "Would set skills.load.extraDirs: [\"$SHARED_SKILLS\"] in $CONFIG_FILE"
        return 0
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "openclaw.json not found — skipping skills.load.extraDirs update"
        log_info "Add manually: skills.load.extraDirs: [\"$SHARED_SKILLS\"]"
        return 0
    fi

    python3 << EOF
import json, sys

config_file = "$CONFIG_FILE"
shared_skills = "$SHARED_SKILLS"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

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

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
except Exception as e:
    print(f"Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    log_success "skills.load.extraDirs configured"
}

# ─── Gateway restart ──────────────────────────────────────────────────────

restart_gateway() {
    log_step "Gateway Restart"

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

# ─── Git commit ───────────────────────────────────────────────────────────────

git_commit() {
    if $DRY_RUN; then
        log_dry "Would prompt: Create git commit? [Y/n]"
        log_dry "Would run: git add -A && git commit -m '[kit] Add openclaw-multiagency kit'"
        return 0
    fi

    echo
    log_info "Git Commit"
    log_info "----------"

    if ! confirm "Create git commit for these changes?" "y"; then
        log_info "Skipped. Commit manually when ready:"
        log_info "  cd $WORKSPACE_DIR && git add -A && git commit -m '[kit] Add openclaw-multiagency kit'"
        return 0
    fi

    # Identity should have been configured in setup_git; verify as a safety net
    local git_name git_email
    git_name=$(git -C "$WORKSPACE_DIR" config user.name 2>/dev/null || true)
    git_email=$(git -C "$WORKSPACE_DIR" config user.email 2>/dev/null || true)

    if [ -z "$git_name" ] || [ -z "$git_email" ]; then
        log_warn "Git identity not configured — cannot commit."
        log_info "  git -C $WORKSPACE_DIR config user.name \"Your Name\""
        log_info "  git -C $WORKSPACE_DIR config user.email \"you@example.com\""
        return 0
    fi

    cd "$WORKSPACE_DIR"
    git add -A

    if git diff --cached --quiet; then
        log_info "Nothing new to commit (workspace already up to date)"
    else
        git commit -m "[kit] Add openclaw-multiagency kit

- Added kit submodule (openclaw-multiagency)
- Created shared/skills/ symlinks
- Registered skills via skills.load.extraDirs in openclaw.json"
        log_success "Changes committed"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    resolve_paths

    echo
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  OpenClaw Multi-Agent Migration                        ║"
        echo "║  DRY RUN MODE — No changes will be made               ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  OpenClaw Multi-Agent Migration                        ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo

    check_prereqs
    setup_git

    # Detect workspace layout
    log_step "Scanning Workspace"
    RESTRUCTURED_AGENT=""
    local layout
    layout=$(detect_layout)

    case "$layout" in
        flat)
            log_info "Detected: single-agent (flat) workspace"
            restructure_flat_workspace
            ;;
        multiagent|multiagency)
            log_info "Detected: multi-agent workspace"
            ;;
        none)
            log_error "No existing agents found in $WORKSPACE_DIR"
            log_info "Agents must have both IDENTITY.md and SOUL.md to be detected."
            log_tip "If this is a fresh install (no agents yet), use the install script:"
            log_tip "  curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagency/main/install.sh | bash"
            exit 1
            ;;
    esac

    # Collect agents (post-restructure if applicable)
    local agents
    agents=$(find_agents)
    log_info "Agents: $agents"

    # Confirm before proceeding
    if ! $DRY_RUN; then
        echo
        log_step "Ready to Migrate"
        log_info "OpenClaw config:  $OPENCLAW_DIR"
        log_info "Workspace:        $WORKSPACE_DIR"
        log_info "Agents:           $agents"
        echo

        local reply=""
        if [ -t 0 ]; then
            read -p "Continue? [Y/n] " -n 1 -r reply
            echo
        elif [ -r /dev/tty ]; then
            printf "Continue? [Y/n] " >&2
            read -r reply < /dev/tty
        fi

        if [[ -n "$reply" && ! "$reply" =~ ^[Yy]$ ]]; then
            log_info "Aborted"
            exit 0
        fi
    fi

    setup_kit
    setup_shared_skills

    log_step "Cleaning Up Agent Directories"
    for agent in $agents; do
        setup_agent_symlinks "$agent"
    done

    # Register restructured agent in openclaw.json if needed
    if [ -n "$RESTRUCTURED_AGENT" ] && ! $DRY_RUN; then
        register_agent_in_config "$RESTRUCTURED_AGENT"
    fi

    update_skills_config
    git_commit
    restart_gateway

    echo
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Dry Run Complete!                                     ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  No changes were made. To run for real:                ║"
        echo "║    ./kit/skills/multiagency-bootstrap/scripts/migrate.sh ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Migration Complete!                                   ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  Next steps:                                           ║"
        echo "║    1. Verify: bash kit/skills/multiagency-kit-guide/    ║"
        echo "║              scripts/check-setup.sh                    ║"
        echo "║    2. Push:   git push origin main                     ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo
}

main "$@"
