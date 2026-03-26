# openclaw-multiagent

Multi-agent workspace toolkit for OpenClaw. Distributed via Git submodules.

## What's This?

A collection of skills and templates for running multiple OpenClaw agents with shared state management, git tracking, and easy Telegram setup.

## When to Use This

| Scenario | What to Run |
|----------|-------------|
| **Fresh OpenClaw install** (no agents yet) | `./kit/skills/multiagent-bootstrap/scripts/setup.sh` |
| **Already have agents** | `./kit/skills/multiagent-bootstrap/scripts/migrate.sh` |

### Fresh Install

Run bootstrap once after installing OpenClaw and before creating any agents.

### Migrating Existing Agents

Already have agents with IDENTITY.md, MEMORY.md, etc.? Use the migration script:

```bash
cd ~/workspaces
git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit
./kit/skills/multiagent-bootstrap/scripts/migrate.sh
```

The migration script:
- Adds the kit as a submodule
- Updates all skill symlinks to point to `kit/skills/`
- Preserves your existing agent data
- Commits the changes

See `skills/multiagent-bootstrap/SKILL.md` for manual migration steps.

## Quick Start (New Install)

```bash
# 1. Create your workspace
mkdir -p ~/workspaces
cd ~/workspaces
git init

# 2. Add this repo as a submodule
git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit

# 3. Run bootstrap (one-time setup)
./kit/skills/multiagent-bootstrap/scripts/setup.sh

# 4. Restart OpenClaw
openclaw gateway restart
```

## What's Included

| Component | Purpose |
|-----------|---------|
| `multiagent-bootstrap` | One-time setup script — creates first agent, wires up config |
| `multiagent-state-manager` | Git workflow for committing workspace changes |
| `multiagent-telegram-setup` | Interactive Telegram bot creation |
| `workspace-template/` | Starter files for new agents (SOUL.md, USER.md, etc.) |

## Creating Additional Agents

After bootstrap, adding agents is manual (for now):

```bash
cd ~/workspaces
cp -r kit/workspace-template my-new-agent
# Edit my-new-agent/IDENTITY.md, USER.md, etc.
# Add to openclaw.json
# Restart OpenClaw
```

## Updating the Kit

```bash
cd ~/workspaces/kit
git pull
cd ..
git add kit
git commit -m "[main] Update multiagent kit"
```

## Structure

```
~/workspaces/
├── kit/                           # this submodule
│   └── skills/
│       ├── multiagent-bootstrap/
│       ├── multiagent-state-manager/
│       └── multiagent-telegram-setup/
├── shared/skills/                 # symlinks to kit
│   ├── multiagent-state-manager -> ../kit/skills/multiagent-state-manager
│   └── multiagent-telegram-setup -> ../kit/skills/multiagent-telegram-setup
└── main/                          # your agent
    └── multiagent-state-manager -> ../shared/skills/multiagent-state-manager
```

## Requirements

- OpenClaw 2026.3.8+
- Git
- Python 3 (for Telegram setup)

## License

MIT
