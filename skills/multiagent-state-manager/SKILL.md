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
./scripts/reminder.sh
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
./scripts/commit_workspace.sh
```

Auto-generates commit message from changed files, adds agent prefix (e.g., `[main]`), includes OpenClaw version/model footer, and **auto-pushes to remote** if configured.

Or provide custom message:

```bash
./scripts/commit_workspace.sh "" "Added email pipeline notes"
```

**Commit format:**
```
[agent] Descriptive message

OpenClaw: <version>
Model: <model-id>
```

### Check what changed

```bash
./scripts/status_summary.sh
```

Shows uncommitted changes, recent commits, and remote status.

### Push to GitHub

```bash
./scripts/push_remote.sh
```

Pushes to `origin/main` by default. Customize:

```bash
./scripts/push_remote.sh "" origin feature-branch
```

## Workflow

1. **Session ends** → Memory/workspace updated
2. **Run status** → Review what changed
3. **Commit** → Checkpoint with message
4. **Push** (optional) → Sync to GitHub

## Scripts

- **commit_workspace.sh** — Stages changes, commits with `[agent]` prefix + metadata footer, and auto-pushes
- **status_summary.sh** — Human-readable git status + recent commits
- **push_remote.sh** — Push to remote repository
- **reminder.sh** — Check for uncommitted changes and prompt user to commit

## Multi-Agent Workspace Support

This skill automatically detects if you're in a **multi-agent workspace** (e.g., `~/agent-workspace/` with subdirs like `main/`, `research/`, `shared/`).

### For Multi-Agent Workspaces

**Commit from any agent directory:**
```bash
cd ~/agent-workspace/main
./scripts/commit_workspace.sh
# Result: [main] Auto-generated message...

cd ../research
./scripts/commit_workspace.sh
# Result: [research] Auto-generated message...
```

**Status shows agent name:**
```
╔════════════════════════════════════════════════════════════╗
║  🤖 Agent: main                                     ║
╠════════════════════════════════════════════════════════════╣
║  📝 Uncommitted changes:                           ║
...
```

### Directory Structure

```
~/agent-workspace/
├── main/                   # main agent workspace
├── research/               # research agent workspace
├── shared/                  # shared resources (main writes, others read)
│   └── skills/
└── .git                   # root git repo
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

On first run, `commit_workspace.sh` auto-initializes git repo.

**Single agent:**
```bash
cd /root/.openclaw/workspace
./scripts/commit_workspace.sh
```

**Multi-agent:**
```bash
cd ~/agent-workspace
# Initialize once at root
git init
```

Then set remote:
```bash
git remote add origin git@github.com:<user>/agent-workspace.git
```

Or via HTTPS:
```bash
git remote add origin https://github.com/<user>/agent-workspace.git
```
