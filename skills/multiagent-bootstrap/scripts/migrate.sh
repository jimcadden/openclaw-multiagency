#!/bin/bash
#
# migrate.sh: Migrate existing OpenClaw agents to the multiagent kit
#
# For users who already have agents set up and want to add the
# openclaw-multiagent kit without losing any existing agent data.
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

KIT_REPO="https://github.com/jimcadden/openclaw-multiagent.git"
WORKSPACE_DIR="${WORKSPACE_DIR:-}"
OPENCLAW_DIR="${OPENCLAW_DIR:-}"
DRY_RUN=false

# ─── Argument parsing ─────────────────────────────────────────────────────────

show_help() {
    echo "OpenClaw Multi-Agent Kit — Migration Script"
    echo ""
    echo "Migrates existing OpenClaw agents to use the multiagent kit."
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

    WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/.openclaw/workspace}"
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

    if [ ! -d "$WORKSPACE_DIR/.git" ]; then
        log_error "No git repository found in $WORKSPACE_DIR"
        log_info "Initialize one first: cd $WORKSPACE_DIR && git init"
        exit 1
    fi
    log_success "Git repository found: $WORKSPACE_DIR"

    log_success "All prerequisites met"
}

# ─── Find existing agents ─────────────────────────────────────────────────────

find_agents() {
    local agents=()
    for dir in "$WORKSPACE_DIR"/*/; do
        # Skip the kit and shared directories
        local name
        name="$(basename "$dir")"
        if [ "$name" = "kit" ] || [ "$name" = "shared" ]; then
            continue
        fi
        if [ -d "$dir" ] && [ -f "${dir}IDENTITY.md" ] && [ -f "${dir}SOUL.md" ]; then
            agents+=("$name")
        fi
    done
    echo "${agents[@]:-}"
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
}

# ─── Shared skills ────────────────────────────────────────────────────────────

setup_shared_skills() {
    log_step "Shared Skills"

    if $DRY_RUN; then
        log_dry "Would create: $WORKSPACE_DIR/shared/skills/"
        for skill in multiagent-state-manager multiagent-telegram-setup multiagent-kit-guide; do
            log_dry "Would symlink: shared/skills/$skill -> ../../kit/skills/$skill"
        done
        return 0
    fi

    mkdir -p "$WORKSPACE_DIR/shared/skills"
    cd "$WORKSPACE_DIR/shared/skills"

    # Remove old-name symlinks from early dev versions
    for old in agent-state-manager telegram-agent-setup; do
        [ -L "$old" ] && rm -f "$old" && log_success "Removed legacy symlink: $old"
    done

    # Remove and recreate to ensure correct target
    for skill in multiagent-state-manager multiagent-telegram-setup multiagent-kit-guide; do
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
                multiagent-state-manager multiagent-telegram-setup multiagent-kit-guide; do
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

# ─── Git commit ───────────────────────────────────────────────────────────────

git_commit() {
    if $DRY_RUN; then
        log_dry "Would prompt: Create git commit? [Y/n]"
        log_dry "Would run: git add -A && git commit -m '[kit] Add openclaw-multiagent kit'"
        return 0
    fi

    echo
    log_info "Git Commit"
    log_info "----------"

    local reply=""
    if [ -t 0 ]; then
        read -p "Create git commit for these changes? [Y/n] " -n 1 -r reply
        echo
    elif [ -r /dev/tty ]; then
        printf "Create git commit for these changes? [Y/n] " >&2
        read -r reply < /dev/tty
    fi

    # Default to yes
    if [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]; then
        local git_name git_email
        git_name=$(git config user.name 2>/dev/null || true)
        git_email=$(git config user.email 2>/dev/null || true)

        if [ -z "$git_name" ] || [ -z "$git_email" ]; then
            log_warn "Git identity not configured — cannot commit."
            log_info "Set your identity and commit manually:"
            log_info "  git config user.name \"Your Name\""
            log_info "  git config user.email \"you@example.com\""
            log_info "  cd $WORKSPACE_DIR && git add -A && git commit -m '[kit] Add openclaw-multiagent kit'"
            return 0
        fi

        cd "$WORKSPACE_DIR"
        git add -A

        if git diff --cached --quiet; then
            log_info "Nothing new to commit (workspace already up to date)"
        else
            git commit -m "[kit] Add openclaw-multiagent kit

- Added kit submodule (openclaw-multiagent)
- Created shared/skills/ symlinks
- Added skill symlinks to all agents"
            log_success "Changes committed"
        fi
    else
        log_info "Skipped. Commit manually when ready:"
        log_info "  cd $WORKSPACE_DIR && git add -A && git commit -m '[kit] Add openclaw-multiagent kit'"
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

    # Find existing agents
    log_step "Scanning Workspace"
    local agents
    agents=$(find_agents)

    if [ -z "$agents" ]; then
        log_error "No existing agents found in $WORKSPACE_DIR"
        log_info "Agents must have both IDENTITY.md and SOUL.md to be detected."
        log_tip "If this is a fresh install (no agents yet), use the install script:"
        log_tip "  curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagent/main/install.sh | bash"
        exit 1
    fi

    log_info "Found agents: $agents"

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

    update_skills_config
    git_commit

    echo
    if $DRY_RUN; then
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Dry Run Complete!                                     ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  No changes were made. To run for real:                ║"
        echo "║    ./kit/skills/multiagent-bootstrap/scripts/migrate.sh ║"
        echo "╚════════════════════════════════════════════════════════╝"
    else
        echo "╔════════════════════════════════════════════════════════╗"
        echo "║  Migration Complete!                                   ║"
        echo "╠════════════════════════════════════════════════════════╣"
        echo "║  Next steps:                                           ║"
        echo "║    1. Verify: bash kit/skills/multiagent-kit-guide/    ║"
        echo "║              scripts/check-setup.sh                    ║"
        echo "║    2. Push:   git push origin main                     ║"
        echo "║    3. Restart: openclaw gateway restart                ║"
        echo "╚════════════════════════════════════════════════════════╝"
    fi
    echo
}

main "$@"
