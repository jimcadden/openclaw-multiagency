#!/bin/bash
#
# update-kit.sh: Interactive kit updater
#
# Updates the kit submodule, re-syncs shared/skills symlinks,
# commits, and restarts the gateway.
#
# Usage: ./update-kit.sh [version]
#   version: tag to update to, or "latest" (default: interactive prompt)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
log_info()    { echo -e "  $1"; }
log_step()    { echo; echo -e "${CYAN}▶ $1${NC}"; }

WORKSPACE_DIR="${WORKSPACE_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.openclaw/workspace")}"
KIT_DIR="$WORKSPACE_DIR/kit"

echo "╔════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Multi-Agent Kit Updater                      ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

cd "$WORKSPACE_DIR"

# ─── Current version ─────────────────────────────────────────────────────

log_step "Current Kit Status"
cd "$KIT_DIR"
current_version=$(git describe --tags 2>/dev/null || git rev-parse --short HEAD)
log_info "Version: $current_version"
log_info "Branch:  $(git branch --show-current 2>/dev/null || echo 'detached')"

# ─── Fetch & select version ─────────────────────────────────────────────

log_step "Fetching Available Versions"
git fetch --tags

echo
echo "Available versions:"
git tag -l | sort -V | tail -10
echo

target_version="${1:-}"
if [ -z "$target_version" ]; then
    read -p "Enter version to update to (or 'latest' for newest): " target_version
fi

if [ "$target_version" = "latest" ]; then
    target_version=$(git tag -l | sort -V | tail -1)
    echo "Latest version: $target_version"
fi

if ! git tag -l | grep -q "^${target_version}$"; then
    echo -e "${RED}✗${NC} Version '$target_version' not found"
    exit 1
fi

if [ "$current_version" = "$target_version" ]; then
    log_success "Already on $target_version"
    echo
    echo "Re-syncing shared skills in case of a previous partial update..."
else
    echo
    echo "Changes from $current_version to $target_version:"
    git log --oneline "${current_version}..${target_version}" 2>/dev/null || echo "  (will show after checkout)"

    echo
    read -p "Proceed with update? [y/N] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    echo
    echo "Updating kit to $target_version..."
    git checkout "$target_version"
    log_success "Kit updated to $target_version"
fi

cd "$WORKSPACE_DIR"
echo "$target_version" > .kit-version
log_success "Wrote .kit-version ($target_version)"

# ─── Re-sync shared/skills symlinks ─────────────────────────────────────

cd "$WORKSPACE_DIR"

log_step "Syncing Shared Skills"

mkdir -p "$WORKSPACE_DIR/shared/skills"

# Migrate old multiagent-* symlinks to multiagency-* (v0.2.x -> v0.3.0+)
for link in "$WORKSPACE_DIR"/shared/skills/multiagent-*; do
    [ -L "$link" ] || continue
    old_name="$(basename "$link")"
    new_name="${old_name/multiagent-/multiagency-}"
    rm -f "$link"
    log_warn "Removed legacy symlink: $old_name (renamed to $new_name)"
done

added=0
for skill_dir in "$KIT_DIR"/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    # Skip internal-only skills that shouldn't be in shared/skills
    case "$skill_name" in
        multiagency-bootstrap|multiagency-kit-guide) continue ;;
    esac
    link="$WORKSPACE_DIR/shared/skills/$skill_name"
    target="../../kit/skills/$skill_name"
    if [ -L "$link" ]; then
        current_target="$(readlink "$link")"
        if [ "$current_target" = "$target" ]; then
            continue
        fi
        rm -f "$link"
    fi
    ln -s "$target" "$link"
    log_success "Linked shared/skills/$skill_name"
    added=$((added + 1))
done

# Remove symlinks for skills no longer in the kit
for link in "$WORKSPACE_DIR"/shared/skills/*; do
    [ -L "$link" ] || continue
    skill_name="$(basename "$link")"
    if [ ! -d "$KIT_DIR/skills/$skill_name" ]; then
        rm -f "$link"
        log_warn "Removed stale symlink: $skill_name"
        added=$((added + 1))
    fi
done

if [ "$added" -eq 0 ]; then
    log_success "Shared skills already in sync"
fi

# ─── Commit ──────────────────────────────────────────────────────────────

log_step "Committing"

git add kit shared/skills

if git diff --cached --quiet; then
    log_success "Nothing new to commit (already up to date)"
else
    echo
    echo "Git status:"
    git status --short
    echo

    read -p "Commit this update? [Y/n] " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        git commit -m "[kit] Update to $target_version

- Updated kit submodule
- Re-synced shared/skills symlinks"
        log_success "Committed"
    else
        echo "Changes staged but not committed."
        echo "Run 'git commit' when ready."
    fi
fi

# ─── Gateway restart ─────────────────────────────────────────────────────

log_step "Gateway Restart"

if command -v openclaw &> /dev/null; then
    echo "Restarting gateway to load updated skills..."
    if openclaw gateway restart 2>/dev/null; then
        log_success "Gateway restarted — updated skills are now available"
    else
        log_warn "Gateway restart failed — restart manually:"
        log_info "  openclaw gateway restart"
    fi
else
    log_warn "openclaw CLI not found — restart the gateway manually:"
    log_info "  openclaw gateway restart"
fi

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Update Complete!                                      ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║  Push when ready: git push origin main                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo
