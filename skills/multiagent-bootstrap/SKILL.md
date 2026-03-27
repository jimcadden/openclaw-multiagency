# multiagent-bootstrap

One-time bootstrap or migration for OpenClaw multi-agent workspace.

## Purpose

- **Bootstrap** — sets up a fresh workspace from scratch: creates the first agent, wires shared skills, and registers the agent in OpenClaw config.
- **Migrate** — adds the multiagent kit to an existing OpenClaw instance that already has agents running, without touching existing agent data.

---

## Bootstrap (Fresh Install)

### When to Use

Use bootstrap when OpenClaw is installed but no agents exist yet.

### Usage

```bash
cd ~/workspaces
./kit/skills/multiagent-bootstrap/scripts/setup.sh
```

Or with an agent name:

```bash
./setup.sh my-agent
```

### Dry Run

```bash
./setup.sh --dry-run
./setup.sh -n my-agent
```

### What It Does

1. Validates environment — checks OpenClaw config, git, python3
2. Creates `shared/skills/` with symlinks into `kit/skills/`
3. Creates first agent from `workspace-template/`
4. Prompts to customize `IDENTITY.md` and `USER.md`
5. Registers agent in `openclaw.json`
6. Optionally runs Telegram setup
7. Prompts to create initial git commit

### Prerequisites

- OpenClaw installed and initialized (`~/.openclaw/openclaw.json` must exist)
- This repo added as submodule at `<workspace>/kit/`
- Git initialized in the workspace directory

### Files Created

```
<workspace>/
├── kit/                       # this submodule (unchanged)
├── shared/
│   └── skills/                # registered via skills.load.extraDirs in openclaw.json
│       ├── multiagent-state-manager  -> ../../kit/skills/multiagent-state-manager
│       ├── multiagent-telegram-setup -> ../../kit/skills/multiagent-telegram-setup
│       └── multiagent-kit-guide      -> ../../kit/skills/multiagent-kit-guide
└── <agent-name>/
    ├── AGENTS.md
    ├── HEARTBEAT.md
    ├── IDENTITY.md
    ├── MEMORY.md
    ├── SOUL.md
    ├── TOOLS.md
    └── USER.md
```

Skills are loaded from `shared/skills/` via `skills.load.extraDirs` in `openclaw.json` — no per-agent symlinks needed.

---

## Migration (Existing Agents)

### When to Use

Use migration when OpenClaw is already running with one or more agents that have `IDENTITY.md` and `SOUL.md`.

### Usage — by hand

```bash
cd <workspace>
./kit/skills/multiagent-bootstrap/scripts/migrate.sh
```

With options:

```bash
./migrate.sh --workspace ~/.openclaw/workspace --openclaw-dir ~/.openclaw
./migrate.sh --dry-run   # preview without making changes
```

### Usage — via agent

If you prefer to have your running agent perform the migration, give it this instruction:

> Read the skill at `<workspace>/kit/skills/multiagent-bootstrap/SKILL.md` and run the migration steps for my existing agents.

The agent will:
1. Read this skill for context
2. Invoke `migrate.sh` (or replicate its steps using file/shell tools)
3. Report back what was changed and prompt for git commit

### What Migration Does

1. Validates prerequisites — git, python3, openclaw dir, openclaw.json
2. Scans workspace for existing agents (directories with `IDENTITY.md` + `SOUL.md`)
3. Shows confirmation summary before making any changes
4. Adds the kit as a git submodule (if not present), checks out latest release tag
5. Creates `shared/skills/` with symlinks to `kit/skills/`
6. Adds per-agent symlinks routing through `shared/skills/`
7. Prompts to create a git commit

### What Migration Does NOT Touch

- `IDENTITY.md`, `MEMORY.md`, `SOUL.md`, `USER.md`, `AGENTS.md` — all preserved
- `openclaw.json` — not modified during migration (agents are already registered)
- Any existing workspace content not related to skill symlinks

### Manual Migration Steps

If you prefer to do it step by step:

```bash
cd <workspace>

# 1. Add the kit as a submodule and pin to latest release
git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit
cd kit
git checkout $(git describe --tags --abbrev=0)
cd ..

# 2. Create shared skills directory
mkdir -p shared/skills
ln -s ../../kit/skills/multiagent-state-manager shared/skills/multiagent-state-manager
ln -s ../../kit/skills/multiagent-telegram-setup shared/skills/multiagent-telegram-setup
ln -s ../../kit/skills/multiagent-kit-guide     shared/skills/multiagent-kit-guide

# 3. Register shared skills in openclaw.json
# Add to ~/.openclaw/openclaw.json:
# "skills": { "load": { "extraDirs": ["<workspace>/shared/skills"] } }

# 4. Commit
git add -A
git commit -m "[kit] Add openclaw-multiagent kit"
```

---

## Post-Bootstrap / Post-Migration

1. Verify the workspace: `bash kit/skills/multiagent-kit-guide/scripts/check-setup.sh`
2. Restart OpenClaw: `openclaw gateway restart`
3. Verify agent loads: `openclaw status`
4. Set up Telegram (if not done): `python3 kit/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py`
