---
name: multiagent-state-manager
description: Manage agent workspace state with git. Part of openclaw-multiagent kit. Use to commit memory and workspace changes, checkpoint session progress, check git status, or push to GitHub. Trigger on commit requests, checkpoint, save state, push to github, what changed, end-of-session wrap-up, or after memory files are updated.
---

# Agent State Manager

Checkpoint your agent workspace state using git. Track changes to memory files, skills, and configuration with commit history.

## When to Use

**Primary trigger:** After a productive session where memory files or workspace have been updated.

**Always remind the user:** When memory files (MEMORY.md, memory/*.md) or key workspace files (TOOLS.md, skills/) have been modified, suggest it's a good time to commit.

**Common scenarios:**
- End of session wrap-up
- After updating memory with new learnings
- Before major workspace changes
- When user asks to "save progress" or "checkpoint"

## Proactive Reminders

### Manual Check

Use the reminder script to check for uncommitted changes and prompt the user:

```bash
{baseDir}/scripts/reminder.sh
```

**When to remind the user:**
- After 30+ minutes of active work
- When memory files have been modified
- Before ending a session
- After completing a significant task

Example reminder message:
> "Memory files have been updated. Want to commit this checkpoint?"

### Automatic Cron Reminder

A cron job runs every 4 hours to automatically check for uncommitted changes:

- **Job:** `Workspace Commit Reminder`
- **Schedule:** Every 4 hours (0:00, 4:00, 8:00, 12:00, 16:00, 20:00 UTC)
- **Action:** Checks git status and sends reminder if changes exist
- **Delivery:** Telegram DM

To disable: `openclaw cron disable <job-id>`
To check status: `openclaw cron list`

## Quick Start

### Commit workspace changes

```bash
{baseDir}/scripts/commit_workspace.sh
```

Auto-generates commit message from changed files, adds agent prefix (e.g., `[main]`), includes OpenClaw version/model footer, and **auto-pushes to remote** if configured.

Or provide custom message:

```bash
{baseDir}/scripts/commit_workspace.sh "" "Added email pipeline notes"
```

**Commit format:**
```
[agent] Descriptive message

OpenClaw: <version>
Model: <model-id>
```

### Check what changed

```bash
{baseDir}/scripts/status_summary.sh
```

Shows uncommitted changes, recent commits, and remote status.

### Push to GitHub

```bash
{baseDir}/scripts/push_remote.sh
```

Pushes to `origin/main` by default. Customize:

```bash
{baseDir}/scripts/push_remote.sh "" origin feature-branch
```

## Workflow

1. **Session ends** → Memory/workspace updated
2. **Run status** → Review what changed
3. **Commit** → Checkpoint with message
4. **Push** (optional) → Sync to GitHub

## Scripts

All scripts are in `{baseDir}/scripts/`:

- **commit_workspace.sh** — Stages changes, commits with `[agent]` prefix + metadata footer, and auto-pushes
- **status_summary.sh** — Human-readable git status + recent commits
- **push_remote.sh** — Push to remote repository
- **reminder.sh** — Check for uncommitted changes and prompt user to commit

## Multi-Agent Workspace Support

This skill automatically detects if you're in a **multi-agent workspace** (a workspace root containing `shared/skills/` alongside individual agent directories).

### For Multi-Agent Workspaces

**Commit from any agent directory:**
```bash
cd <workspace>/<agent-name>
./multiagent-state-manager/scripts/commit_workspace.sh
# Result: [<agent-name>] Auto-generated message...
```

The agent name is derived automatically from the current directory name.

### Directory Structure

```
<workspace>/
├── <agent-name>/           # your agent workspace
├── shared/
│   └── skills/             # shared skill symlinks
└── .git                    # root git repo
```

## Commit Message Format

Include system metadata in commit messages:

```
<descriptive title>

OpenClaw: <version> (<commit-hash>)
Model: <model-id>
```

Example:
```
[main] Memory files - Session checkpoint

OpenClaw: 2026.3.8 (3caab92)
Model: rits-qwen3.5/Qwen/Qwen3.5-397B-A17B-FP8
```

This tracks which system version and model created each checkpoint.

## First-Time Setup

The workspace git repo is initialized by `install.sh` or `migrate.sh`. To add a remote for push/pull:

```bash
cd <workspace>
git remote add origin git@github.com:<user>/workspaces.git
# or via HTTPS:
git remote add origin https://github.com/<user>/workspaces.git
```
