#!/bin/bash
#
# test-install.sh — Smoke tests for install.sh
#
# Tests each scenario in isolation using a temporary HOME and stub binaries.
# No external dependencies required beyond bash, git, and python3.
#
# Usage:
#   bash scripts/test-install.sh           # run all tests
#   bash scripts/test-install.sh <name>    # run tests matching name substring

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

# ─── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}  PASS${NC}  $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}  FAIL${NC}  $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo -e "${CYAN}▶ $1${NC}"; }

# ─── Env helpers ──────────────────────────────────────────────────────────────

TMP_HOME=""

setup_env() {
    TMP_HOME="$(mktemp -d)"
    TMP_BIN="$TMP_HOME/bin"
    TMP_WORKSPACE="$TMP_HOME/workspaces"
    TMP_OC_DIR="$TMP_HOME/.openclaw"
    mkdir -p "$TMP_BIN"
}

teardown_env() {
    [ -n "$TMP_HOME" ] && rm -rf "$TMP_HOME"
    TMP_HOME=""
}

stub_bin() {
    local name="$1" output="${2:-}" exit_code="${3:-0}"
    printf '#!/bin/bash\n%s\nexit %s\n' "${output:+echo \"$output\"}" "$exit_code" \
        > "$TMP_BIN/$name"
    chmod +x "$TMP_BIN/$name"
}

setup_openclaw() {
    mkdir -p "$TMP_OC_DIR"
    printf '{"agents":{"list":[]}}\n' > "$TMP_OC_DIR/openclaw.json"
}

setup_git_identity() {
    printf '[user]\n    name = Test User\n    email = test@example.com\n' \
        > "$TMP_HOME/.gitconfig"
}

# Run install.sh with given extra args plus fixed workspace/agent/openclaw-dir.
# Captures output into $OUT and exit code into $RC.
run_install() {
    local extra_args=("$@")
    set +e
    OUT=$(
        HOME="$TMP_HOME" \
        PATH="$TMP_BIN:/usr/bin:/bin" \
        GIT_CONFIG_GLOBAL="$TMP_HOME/.gitconfig" \
            bash "$INSTALL_SH" \
                --workspace "$TMP_WORKSPACE" \
                --agent testbot \
                "${extra_args[@]}" \
            < /dev/null 2>&1
    )
    RC=$?
    set -e
}

# Run install.sh with fully custom args (no defaults added).
run_install_raw() {
    set +e
    OUT=$(
        HOME="$TMP_HOME" \
        PATH="$TMP_BIN:/usr/bin:/bin" \
        GIT_CONFIG_GLOBAL="$TMP_HOME/.gitconfig" \
            bash "$INSTALL_SH" "$@" < /dev/null 2>&1
    )
    RC=$?
    set -e
}

out_contains() {
    [[ "$OUT" == *"$1"* ]]
}

# ─── Filter ───────────────────────────────────────────────────────────────────

FILTER="${1:-}"
should_run() { [[ -z "$FILTER" || "$1" == *"$FILTER"* ]]; }

# ─── Tests ────────────────────────────────────────────────────────────────────

section "Argument parsing"

if should_run "unknown_flag"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_install_raw --not-a-real-flag
    if [ "$RC" -ne 0 ] && out_contains "Unknown option"; then
        pass "unknown_flag: exits non-zero with 'Unknown option' message"
    else
        fail "unknown_flag: expected non-zero exit + 'Unknown option' (RC=$RC)"
        echo "  output: $OUT"
    fi
    teardown_env
fi

if should_run "missing_workspace_value"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_install_raw --workspace
    if [ "$RC" -ne 0 ] && out_contains "--workspace requires"; then
        pass "missing_workspace_value: exits non-zero with clear message"
    else
        fail "missing_workspace_value: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "missing_agent_value"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_install_raw --agent --workspace /tmp
    if [ "$RC" -ne 0 ] && out_contains "--agent requires"; then
        pass "missing_agent_value: exits non-zero with clear message"
    else
        fail "missing_agent_value: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "missing_openclaw_dir_value"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_install_raw --openclaw-dir --workspace /tmp
    if [ "$RC" -ne 0 ] && out_contains "--openclaw-dir requires"; then
        pass "missing_openclaw_dir_value: exits non-zero with clear message"
    else
        fail "missing_openclaw_dir_value: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

section "Prerequisites — git"

if should_run "missing_git"; then
    setup_env
    # git NOT stubbed — PATH only has TMP_BIN and coreutils
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_install --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "git"; then
        pass "missing_git: exits non-zero with 'git' in message"
    else
        fail "missing_git: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

section "Prerequisites — python3"

if should_run "missing_python3"; then
    setup_env
    stub_bin "git" "git version 2.x"
    # python3 NOT stubbed
    setup_openclaw
    setup_git_identity
    run_install --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "python3"; then
        pass "missing_python3: exits non-zero with 'python3' in message"
    else
        fail "missing_python3: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

section "Prerequisites — OpenClaw config"

if should_run "missing_openclaw_dir"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    # TMP_OC_DIR not created
    setup_git_identity
    run_install --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "not found"; then
        pass "missing_openclaw_dir: exits non-zero before workspace creation"
    else
        fail "missing_openclaw_dir: RC=$RC, output: $OUT"
    fi
    # Workspace must NOT have been created
    if [ ! -d "$TMP_WORKSPACE" ]; then
        pass "missing_openclaw_dir: workspace was not created (no partial state)"
    else
        fail "missing_openclaw_dir: workspace was created before prereqs passed"
    fi
    teardown_env
fi

if should_run "missing_openclaw_json"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    mkdir -p "$TMP_OC_DIR"
    # Directory exists but openclaw.json absent
    setup_git_identity
    run_install --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "openclaw.json"; then
        pass "missing_openclaw_json: exits non-zero with 'openclaw.json' in message"
    else
        fail "missing_openclaw_json: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "custom_openclaw_dir"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    CUSTOM_OC="$TMP_HOME/custom-oc"
    mkdir -p "$CUSTOM_OC"
    printf '{"agents":{"list":[]}}\n' > "$CUSTOM_OC/openclaw.json"
    setup_git_identity
    # Run with custom dir — will proceed past prereqs then fail at git submodule add
    # (expected in isolated env). We only verify prereqs passed.
    run_install --openclaw-dir "$CUSTOM_OC"
    if out_contains "All prerequisites met"; then
        pass "custom_openclaw_dir: prereqs pass when --openclaw-dir points at valid config"
    else
        fail "custom_openclaw_dir: prereqs failed despite valid custom dir (RC=$RC)"
        echo "  output: $OUT"
    fi
    teardown_env
fi

section "Prerequisites — all pass"

if should_run "prereqs_all_pass"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_install --openclaw-dir "$TMP_OC_DIR"
    if out_contains "All prerequisites met"; then
        pass "prereqs_all_pass: all checks pass with valid environment"
    else
        fail "prereqs_all_pass: prereqs did not pass (RC=$RC)"
        echo "  output: $OUT"
    fi
    teardown_env
fi

# ─── migrate.sh tests ─────────────────────────────────────────────────────────

MIGRATE_SH="$REPO_ROOT/skills/multiagent-bootstrap/scripts/migrate.sh"

# Run migrate.sh with given args in the isolated environment.
run_migrate() {
    set +e
    OUT=$(
        HOME="$TMP_HOME" \
        PATH="$TMP_BIN:/usr/bin:/bin" \
        GIT_CONFIG_GLOBAL="$TMP_HOME/.gitconfig" \
            bash "$MIGRATE_SH" "$@" < /dev/null 2>&1
    )
    RC=$?
    set -e
}

# Create a minimal agent directory (has IDENTITY.md + SOUL.md).
make_agent_dir() {
    local ws="$1" name="$2"
    mkdir -p "$ws/$name"
    printf "# IDENTITY\n" > "$ws/$name/IDENTITY.md"
    printf "# SOUL\n"     > "$ws/$name/SOUL.md"
}

# Init a bare git repo in workspace (no identity needed for init).
init_workspace_git() {
    local ws="$1"
    mkdir -p "$ws"
    git -C "$ws" init -q
}

section "migrate.sh — argument parsing"

if should_run "migrate_unknown_flag"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_migrate --not-a-real-flag
    if [ "$RC" -ne 0 ] && out_contains "Unknown option"; then
        pass "migrate_unknown_flag: exits non-zero with 'Unknown option'"
    else
        fail "migrate_unknown_flag: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_missing_workspace_value"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_migrate --workspace
    if [ "$RC" -ne 0 ] && out_contains "--workspace requires"; then
        pass "migrate_missing_workspace_value: exits non-zero with clear message"
    else
        fail "migrate_missing_workspace_value: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_missing_openclaw_dir_value"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    run_migrate --openclaw-dir
    if [ "$RC" -ne 0 ] && out_contains "--openclaw-dir requires"; then
        pass "migrate_missing_openclaw_dir_value: exits non-zero with clear message"
    else
        fail "migrate_missing_openclaw_dir_value: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

section "migrate.sh — prerequisites"

if should_run "migrate_missing_python3"; then
    setup_env
    stub_bin "git" "git version 2.x"
    # python3 NOT stubbed
    setup_openclaw
    setup_git_identity
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "python3"; then
        pass "migrate_missing_python3: exits non-zero with 'python3' in message"
    else
        fail "migrate_missing_python3: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_missing_openclaw_json"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    mkdir -p "$TMP_OC_DIR"  # dir exists but no openclaw.json
    setup_git_identity
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "openclaw.json"; then
        pass "migrate_missing_openclaw_json: exits non-zero with 'openclaw.json' in message"
    else
        fail "migrate_missing_openclaw_json: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_workspace_not_found"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    # TMP_WORKSPACE not created
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "not found"; then
        pass "migrate_workspace_not_found: exits non-zero with 'not found' message"
    else
        fail "migrate_workspace_not_found: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_workspace_no_git"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    mkdir -p "$TMP_WORKSPACE"  # exists but no .git
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "git"; then
        pass "migrate_workspace_no_git: exits non-zero with 'git' message"
    else
        fail "migrate_workspace_no_git: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_no_agents_found"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    init_workspace_git "$TMP_WORKSPACE"
    # Workspace exists and has .git, but no agent dirs
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -ne 0 ] && out_contains "No existing agents found"; then
        pass "migrate_no_agents_found: exits non-zero with clear message"
    else
        fail "migrate_no_agents_found: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

section "migrate.sh — dry run with agents"

if should_run "migrate_dry_run"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    init_workspace_git "$TMP_WORKSPACE"
    make_agent_dir "$TMP_WORKSPACE" "myagent"
    run_migrate --dry-run --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if [ "$RC" -eq 0 ] && out_contains "DRY RUN"; then
        pass "migrate_dry_run: exits 0 and shows DRY RUN banner"
    else
        fail "migrate_dry_run: RC=$RC, output: $OUT"
    fi
    if [ ! -d "$TMP_WORKSPACE/kit" ] && [ ! -d "$TMP_WORKSPACE/shared" ]; then
        pass "migrate_dry_run: no filesystem changes made"
    else
        fail "migrate_dry_run: dry run created files it should not have"
    fi
    if out_contains "extraDirs"; then
        pass "migrate_dry_run: dry run shows extraDirs config step"
    else
        fail "migrate_dry_run: expected extraDirs mention in dry run output"
    fi
    teardown_env
fi

section "migrate.sh — flat workspace detection"

if should_run "migrate_flat_layout_detected"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    init_workspace_git "$TMP_WORKSPACE"
    # Flat layout: agent files at workspace root, not in subdir
    printf "# IDENTITY\n" > "$TMP_WORKSPACE/IDENTITY.md"
    printf "# SOUL\n"     > "$TMP_WORKSPACE/SOUL.md"
    run_migrate --dry-run --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if out_contains "flat"; then
        pass "migrate_flat_layout_detected: flat layout detected in dry run"
    else
        fail "migrate_flat_layout_detected: RC=$RC, output: $OUT"
        echo "  output: $OUT"
    fi
    teardown_env
fi

if should_run "migrate_flat_restructure_dry_run"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    init_workspace_git "$TMP_WORKSPACE"
    printf "# IDENTITY\n" > "$TMP_WORKSPACE/IDENTITY.md"
    printf "# SOUL\n"     > "$TMP_WORKSPACE/SOUL.md"
    printf "# MEMORY\n"   > "$TMP_WORKSPACE/MEMORY.md"
    run_migrate --dry-run --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if out_contains "Would move" || out_contains "Would create"; then
        pass "migrate_flat_restructure_dry_run: shows restructure plan"
    else
        fail "migrate_flat_restructure_dry_run: RC=$RC"
        echo "  output: $OUT"
    fi
    teardown_env
fi

section "migrate.sh — no git repo (offer to init)"

if should_run "migrate_no_git_offers_init"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    mkdir -p "$TMP_WORKSPACE"
    # No .git — workspace exists but is not a repo
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if out_contains "Initialize git"; then
        pass "migrate_no_git_offers_init: prompts to initialize git repo"
    else
        fail "migrate_no_git_offers_init: RC=$RC, output: $OUT"
    fi
    teardown_env
fi

section "migrate.sh — prereqs all pass"

if should_run "migrate_prereqs_all_pass"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    init_workspace_git "$TMP_WORKSPACE"
    make_agent_dir "$TMP_WORKSPACE" "myagent"
    run_migrate --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if out_contains "All prerequisites met"; then
        pass "migrate_prereqs_all_pass: prereqs pass with valid environment and agents"
    else
        fail "migrate_prereqs_all_pass: prereqs failed (RC=$RC)"
        echo "  output: $OUT"
    fi
    teardown_env
fi

section "migrate.sh — shared skills include add-agent, exclude kit-guide"

if should_run "migrate_shared_skills_set"; then
    setup_env
    stub_bin "git" "git version 2.x"
    stub_bin "python3" "Python 3.x"
    setup_openclaw
    setup_git_identity
    init_workspace_git "$TMP_WORKSPACE"
    make_agent_dir "$TMP_WORKSPACE" "myagent"
    run_migrate --dry-run --workspace "$TMP_WORKSPACE" --openclaw-dir "$TMP_OC_DIR"
    if out_contains "multiagent-add-agent"; then
        pass "migrate_shared_skills_set: multiagent-add-agent included in shared skills"
    else
        fail "migrate_shared_skills_set: multiagent-add-agent missing from dry run output"
    fi
    if ! out_contains "multiagent-kit-guide"; then
        pass "migrate_shared_skills_set: multiagent-kit-guide not in shared skills"
    else
        fail "migrate_shared_skills_set: multiagent-kit-guide should not be in shared skills"
    fi
    teardown_env
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo
echo "╔════════════════════════════════════════════════════════╗"
if [ "$FAIL" -eq 0 ]; then
    printf "║  All %d tests passed                                   ║\n" "$PASS"
else
    printf "║  %d passed, %d FAILED                                  ║\n" "$PASS" "$FAIL"
fi
echo "╚════════════════════════════════════════════════════════╝"
echo

[ "$FAIL" -eq 0 ]
