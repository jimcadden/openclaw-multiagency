# openclaw-multiagency

Multi-agent workspace toolkit for OpenClaw. Distributed via Git submodules.

## What's This?

A collection of skills and templates for running multiple OpenClaw agents with shared state management, git tracking, and easy Telegram/Discord setup.

## Quick Install (Recommended)

One-liner for fresh OpenClaw installs:

```bash
curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagency/main/install.sh | bash
```

With options:
```bash
curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagency/main/install.sh | bash -s -- --workspace ~/my-agents --agent assistant
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `-w, --workspace DIR` | `~/workspaces` | Directory where agent workspaces are created |
| `-a, --agent NAME` | `main` | Name of the first agent |
| `-c, --openclaw-dir DIR` | `~/.openclaw` | Path to OpenClaw config directory (use if OpenClaw is installed in a non-default location) |

**Requirements before running:**
- OpenClaw must be installed and initialized (`~/.openclaw/openclaw.json` must exist)
- `git` and `python3` must be on your PATH

## When to Use This

| Scenario | What to Run |
|----------|-------------|
| **Fresh OpenClaw install** (no agents yet) | `curl .../install.sh \| bash` (above) |
| **Already have agents** | `./kit/skills/multiagency-bootstrap/scripts/migrate.sh` |

### Fresh Install

The install script handles everything:
- Creates your workspace directory
- Initializes git repo
- Adds the kit as a submodule
- Checks out the latest stable tag
- Runs bootstrap to create your first agent

### Migrating Existing Agents

Already have agents with IDENTITY.md, MEMORY.md, etc.? Use the migration script:

```bash
./kit/skills/multiagency-bootstrap/scripts/migrate.sh
```

With options (defaults shown):
```bash
./kit/skills/multiagency-bootstrap/scripts/migrate.sh --workspace ~/.openclaw/workspace --openclaw-dir ~/.openclaw
./kit/skills/multiagency-bootstrap/scripts/migrate.sh --dry-run   # preview changes without making them
```

The migration script:
- Validates prereqs (git, python3, openclaw config) before touching anything
- Adds the kit as a git submodule and checks out the latest release tag
- Creates `shared/skills/` with kit symlinks
- Wires per-agent symlinks through `shared/skills/`
- Preserves all existing agent data (IDENTITY.md, MEMORY.md, etc.)
- Prompts before committing

See `skills/multiagency-bootstrap/SKILL.md` for manual steps and agent-driven migration.

## What's Included

| Component | Purpose |
|-----------|---------|
| `multiagency-bootstrap` | One-time setup script — creates first agent, wires up config |
| `multiagency-add-agent` | Add additional agents to an existing workspace |
| `multiagency-state-manager` | Git workflow for committing workspace changes |
| `multiagency-telegram-setup` | Interactive Telegram bot creation |
| `multiagency-discord-setup` | Interactive Discord bot creation |
| `multiagency-kit-guide` | Quick reference for kit usage, update and health-check scripts |
| `workspace-template/` | Starter files for new agents (SOUL.md, USER.md, etc.) |

## Creating Agents

After the initial setup, you can add more agents using the add-agent script:

```bash
cd ~/workspaces
bash kit/skills/multiagency-add-agent/scripts/add-agent.sh my-new-agent
```

The script walks you through identity customization, optional Telegram/Discord bot setup, and commits the result.

**Examples:**

```bash
# Basic — prompts for agent name interactively
bash kit/skills/multiagency-add-agent/scripts/add-agent.sh

# Pass the name directly
bash kit/skills/multiagency-add-agent/scripts/add-agent.sh research

# Use a non-default workspace location
WORKSPACE_DIR=~/my-agents bash kit/skills/multiagency-add-agent/scripts/add-agent.sh writer

# Use a non-default OpenClaw config directory
OPENCLAW_DIR=~/.config/openclaw bash kit/skills/multiagency-add-agent/scripts/add-agent.sh assistant
```

## Updating the Kit

From within your workspace directory, run the update script:

```bash
cd ~/workspaces
bash kit/skills/multiagency-kit-guide/scripts/update-kit.sh
```

The script will show available versions and prompt you to choose. You can also specify a version directly:

```bash
# Update to a specific version
bash kit/skills/multiagency-kit-guide/scripts/update-kit.sh v0.3.1

# Update to the latest version without prompts
bash kit/skills/multiagency-kit-guide/scripts/update-kit.sh latest --yes
```

The update script handles everything: fetches the latest tags, checks out the selected version, re-syncs `shared/skills` symlinks, syncs workspace-template changes to existing agents, commits, and restarts the gateway.

## Structure

```
~/workspaces/
├── kit/                           # this submodule
│   └── skills/
│       ├── multiagency-bootstrap/
│       ├── multiagency-add-agent/
│       ├── multiagency-state-manager/
│       ├── multiagency-telegram-setup/
│       ├── multiagency-discord-setup/
│       └── multiagency-kit-guide/
├── shared/skills/                 # symlinks to kit
│   ├── multiagency-state-manager -> ../kit/skills/multiagency-state-manager
│   ├── multiagency-telegram-setup -> ../kit/skills/multiagency-telegram-setup
│   └── multiagency-discord-setup  -> ../kit/skills/multiagency-discord-setup
└── main/                          # your agent
    └── multiagency-state-manager -> ../shared/skills/multiagency-state-manager
```

## Requirements

- OpenClaw 2026.3.8+ (must be initialized — `~/.openclaw/openclaw.json` must exist)
- Git
- Python 3 (for config updates and channel setup scripts)

## Verifying Your Install

After running the install script, use the health check to verify the workspace is correctly wired up:

```bash
bash ~/workspaces/kit/skills/multiagency-kit-guide/scripts/check-setup.sh
```

Expected output:
```
✅ Kit directory exists
✅ Kit is a git repo
✅ Kit is on a tagged release
✅ multiagency-state-manager symlink exists
✅ multiagency-telegram-setup symlink exists
✅ multiagency-discord-setup symlink exists
✅ <agent-name>
✅ Git repository initialized
```

**Running the installer smoke tests** (for contributors and testers):

```bash
bash scripts/test-install.sh
```

This exercises all installer failure modes in isolation — unknown flags, missing prereqs, missing config — without touching any real OpenClaw state.

## License

MIT
