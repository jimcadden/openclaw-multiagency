#!/bin/bash
#
# remove-agent.sh: Remove an agent from the multiagency workspace
#
# Usage:
#   ./remove-agent.sh <agent-name> [OPTIONS]
#
# Options:
#   --dry-run    Preview changes without making them
#   --delete     Permanently delete workspace instead of archiving
#   --help       Show this help

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
log_dry()     { echo -e "${CYAN}[DRY RUN]${NC} $1"; }
log_step()    { echo; echo -e "${CYAN}▶ $1${NC}"; }

# ─── Path detection ───────────────────────────────────────────────────────────

# Script lives at: <workspace>/kit/skills/multiagency-remove-agent/scripts/remove-agent.sh
# Five levels up = workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_WORKSPACE="$(dirname "$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")")"

if [ -z "${WORKSPACE_DIR:-}" ]; then
    if [ -d "$AUTO_WORKSPACE/kit" ]; then
        WORKSPACE_DIR="$AUTO_WORKSPACE"
    else
        WORKSPACE_DIR="$HOME/.openclaw/workspace"
    fi
fi

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

# ─── Argument parsing ─────────────────────────────────────────────────────────

AGENT_NAME=""
DRY_RUN=false
HARD_DELETE=false

show_help() {
    echo "Usage: remove-agent.sh <agent-name> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Preview changes without making them"
    echo "  --delete     Permanently delete workspace (default: archive)"
    echo "  --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  remove-agent.sh myagent --dry-run"
    echo "  remove-agent.sh myagent"
    echo "  remove-agent.sh myagent --delete"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n) DRY_RUN=true; shift ;;
        --delete)     HARD_DELETE=true; shift ;;
        --help|-h)    show_help; exit 0 ;;
        -*)
            log_error "Unknown option: $1"
            show_help; exit 1 ;;
        *)
            if [ -z "$AGENT_NAME" ]; then
                AGENT_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                exit 1
            fi
            shift ;;
    esac
done

if [ -z "$AGENT_NAME" ]; then
    log_error "Agent name is required"
    show_help
    exit 1
fi

# ─── Validate agent exists ────────────────────────────────────────────────────

AGENT_DIR="$WORKSPACE_DIR/$AGENT_NAME"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"
ARCHIVE_NAME="${AGENT_NAME}.archived.$(date +%Y-%m-%d)"
ARCHIVE_DIR="$WORKSPACE_DIR/$ARCHIVE_NAME"

if ! $DRY_RUN && [ ! -d "$AGENT_DIR" ]; then
    log_error "Agent directory not found: $AGENT_DIR"
    exit 1
fi

# ─── Detect Telegram config ───────────────────────────────────────────────────

# Find any Telegram account IDs and bindings associated with this agent
detect_telegram() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi
    python3 << EOF
import json, sys

try:
    with open("$CONFIG_FILE") as f:
        config = json.load(f)

    agent_id = "$AGENT_NAME"
    bindings = config.get("bindings", [])
    accounts = config.get("channels", {}).get("telegram", {}).get("accounts", {})

    # Find bindings for this agent
    agent_bindings = [b for b in bindings if b.get("agentId") == agent_id]

    # Find account IDs referenced in those bindings
    account_ids = [b.get("match", {}).get("accountId") for b in agent_bindings
                   if b.get("match", {}).get("channel") == "telegram"]
    account_ids = [a for a in account_ids if a]  # remove None

    if account_ids:
        print("found:" + ",".join(account_ids))
    else:
        print("none")
except Exception as e:
    print("none")
EOF
}

TELEGRAM_RESULT=$(detect_telegram 2>/dev/null || echo "none")
TELEGRAM_ACCOUNTS=""
if [[ "$TELEGRAM_RESULT" == found:* ]]; then
    TELEGRAM_ACCOUNTS="${TELEGRAM_RESULT#found:}"
fi

# ─── Banner ───────────────────────────────────────────────────────────────────

echo
if $DRY_RUN; then
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Remove Agent — DRY RUN                               ║"
    echo "╚════════════════════════════════════════════════════════╝"
else
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  Remove Agent                                          ║"
    echo "╚════════════════════════════════════════════════════════╝"
fi
echo

# ─── Show plan ────────────────────────────────────────────────────────────────

log_step "Removal Plan"
log_info "Agent:      $AGENT_NAME"
log_info "Workspace:  $AGENT_DIR"

if $HARD_DELETE; then
    log_warn "Workspace:  PERMANENTLY DELETE (--delete flag set)"
else
    log_info "Workspace:  archive as $ARCHIVE_NAME"
fi

if [ -n "$TELEGRAM_ACCOUNTS" ]; then
    IFS=',' read -ra ACCT_LIST <<< "$TELEGRAM_ACCOUNTS"
    for acct in "${ACCT_LIST[@]}"; do
        log_info "Telegram:   remove account '$acct' + binding from openclaw.json"
    done
    echo
    log_warn "Bot tokens remain active until you run /deletebot in @BotFather"
fi

log_info "Config:     remove from openclaw.json agents.list"
log_info "Git:        commit removal"

if $DRY_RUN; then
    echo
    log_dry "No changes made. Re-run without --dry-run to proceed."
    echo
    exit 0
fi

# ─── Confirmation ─────────────────────────────────────────────────────────────

echo
if $HARD_DELETE; then
    log_warn "This will PERMANENTLY DELETE $AGENT_DIR and all its contents."
    log_warn "This cannot be undone."
else
    log_info "The workspace will be archived (not deleted). You can restore it later."
fi
echo

reply=""
if [ -t 0 ]; then
    read -p "Remove agent '$AGENT_NAME'? [y/N] " -n 1 -r reply
    echo
elif [ -r /dev/tty ]; then
    printf "Remove agent '%s'? [y/N] " "$AGENT_NAME" >&2
    read -r reply < /dev/tty
fi

if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    log_info "Aborted"
    exit 0
fi

# ─── Remove from openclaw.json ────────────────────────────────────────────────

log_step "Updating OpenClaw Config"

if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "openclaw.json not found at $CONFIG_FILE — skipping config update"
else
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d-%H%M%S)"

    python3 << EOF
import json, sys

config_file = "$CONFIG_FILE"
agent_id = "$AGENT_NAME"
telegram_accounts_str = "$TELEGRAM_ACCOUNTS"
telegram_accounts = [a for a in telegram_accounts_str.split(",") if a]

try:
    with open(config_file) as f:
        config = json.load(f)

    # Remove from agents.list
    original_count = len(config.get("agents", {}).get("list", []))
    if "agents" in config and "list" in config["agents"]:
        config["agents"]["list"] = [
            a for a in config["agents"]["list"] if a.get("id") != agent_id
        ]
        removed = original_count - len(config["agents"]["list"])
        print(f"Removed {removed} agent entry from agents.list")

    # Remove Telegram accounts and bindings
    if telegram_accounts:
        accounts = config.get("channels", {}).get("telegram", {}).get("accounts", {})
        for acct_id in telegram_accounts:
            if acct_id in accounts:
                del accounts[acct_id]
                print(f"Removed Telegram account: {acct_id}")

        bindings = config.get("bindings", [])
        before = len(bindings)
        config["bindings"] = [
            b for b in bindings
            if not (b.get("agentId") == agent_id and
                    b.get("match", {}).get("channel") == "telegram")
        ]
        removed_bindings = before - len(config["bindings"])
        if removed_bindings:
            print(f"Removed {removed_bindings} Telegram binding(s)")

    with open(config_file, "w") as f:
        json.dump(config, f, indent=2)

except Exception as e:
    print(f"Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
EOF

    log_success "openclaw.json updated"
fi

# ─── Handle workspace directory ───────────────────────────────────────────────

log_step "Workspace"

cd "$WORKSPACE_DIR"

if $HARD_DELETE; then
    if [ -d "$AGENT_DIR/.git" ] || git ls-files --error-unmatch "$AGENT_NAME/" &>/dev/null 2>&1; then
        git rm -rf "$AGENT_NAME/"
        log_success "Deleted $AGENT_NAME/ (via git rm)"
    else
        rm -rf "$AGENT_DIR"
        log_success "Deleted $AGENT_DIR"
    fi
else
    if git ls-files --error-unmatch "$AGENT_NAME/" &>/dev/null 2>&1; then
        git mv "$AGENT_NAME" "$ARCHIVE_NAME"
    else
        mv "$AGENT_DIR" "$ARCHIVE_DIR"
    fi
    log_success "Archived as $ARCHIVE_NAME"
fi

# ─── Git commit ───────────────────────────────────────────────────────────────

log_step "Git Commit"

git_name=$(git config user.name 2>/dev/null || true)
git_email=$(git config user.email 2>/dev/null || true)

if [ -z "$git_name" ] || [ -z "$git_email" ]; then
    log_warn "Git identity not configured — skipping commit."
    log_info "  git config user.name \"Your Name\""
    log_info "  git config user.email \"you@example.com\""
    log_info "  cd $WORKSPACE_DIR && git add -A && git commit -m \"[kit] Remove agent $AGENT_NAME\""
else
    git add -A
    if ! git diff --cached --quiet; then
        ACTION="archived"
        $HARD_DELETE && ACTION="deleted"
        git commit -m "[kit] Remove agent $AGENT_NAME

- $ACTION workspace directory
- Removed from openclaw.json agents.list
$([ -n "$TELEGRAM_ACCOUNTS" ] && echo "- Removed Telegram account(s): $TELEGRAM_ACCOUNTS")"
        log_success "Changes committed"
    else
        log_info "Nothing to commit"
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║  Agent Removed                                         ║"
echo "╠════════════════════════════════════════════════════════╣"
if ! $HARD_DELETE; then
    printf "║  Archived: %-44s ║\n" "$ARCHIVE_NAME/"
fi
if [ -n "$TELEGRAM_ACCOUNTS" ]; then
    echo "║                                                        ║"
    echo "║  ⚠  Telegram bot token still active!                  ║"
    echo "║     Message @BotFather and run /deletebot              ║"
    echo "║     to fully decommission the bot.                     ║"
fi
echo "║                                                        ║"
echo "║  Restart OpenClaw: openclaw gateway restart            ║"
echo "╚════════════════════════════════════════════════════════╝"
echo
