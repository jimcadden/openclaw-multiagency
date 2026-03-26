# openclaw-multiagent

Multi-agent workspace toolkit for OpenClaw. Distributed via Git submodules.

## What's This?

A collection of skills and templates for running multiple OpenClaw agents with shared state management, git tracking, and easy Telegram setup.

## Quick Install (Recommended)

One-liner for fresh OpenClaw installs:

```bash
curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagent/main/install.sh | bash
```

With options:
```bash
curl -fsSL https://raw.githubusercontent.com/jimcadden/openclaw-multiagent/main/install.sh | bash -s -- --workspace ~/my-agents --agent assistant
```

## When to Use This

| Scenario | What to Run |
|----------|-------------|
| **Fresh OpenClaw install** (no agents yet) | `curl .../install.sh \| bash` (above) |
| **Already have agents** | `./kit/skills/multiagent-bootstrap/scripts/migrate.sh` |

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
cd ~/workspaces
git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit
cd kit && git checkout v0.2.2 && cd ..
./kit/skills/multiagent-bootstrap/scripts/migrate.sh
```

The migration script:
- Adds the kit as a submodule
- Updates all skill symlinks to point to `kit/skills/`
- Preserves your existing agent data
- Commits the changes

See `skills/multiagent-bootstrap/SKILL.md` for manual migration steps.

## Manual Install (Old Way)

If you prefer manual setup:

```bash
# 1. Create your workspace
mkdir -p ~/workspaces
cd ~/workspaces
git init

# 2. Add this repo as a submodule
git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit

# 3. Checkout a stable version
cd kit && git checkout v0.2.2 && cd ..

# 4. Run bootstrap (one-time setup)
./kit/skills/multiagent-bootstrap/scripts/setup.sh

# 5. Restart OpenClaw
openclaw gateway restart
```

## What's Included

| Component | Purpose |
|-----------|---------|
| `multiagent-bootstrap` | One-time setup script — creates first agent, wires up config |
| `multiagent-state-manager` | Git workflow for committing workspace changes |
| `multiagent-telegram-setup` | Interactive Telegram bot creation |
| `multiagent-kit-guide` | Quick reference for kit usage |
| `workspace-template/` | Starter files for new agents (SOUL.md, USER.md, etc.) |

## Creating Additional Agents

After the initial setup, you can add more agents:

**Quick way (recommended):**
```bash
cd ~/workspaces
./kit/scripts/add-agent.sh my-new-agent
# Script handles: workspace, identity customization, Telegram prompt, git commit
```

**Manual way:**
```bash
cd ~/workspaces
cp -r kit/workspace-template my-new-agent
# Edit my-new-agent/IDENTITY.md, USER.md
# Add agent to ~/.openclaw/openclaw.json
# Restart OpenClaw: openclaw gateway restart
```

## Updating the Kit

```bash
cd ~/workspaces/kit
git fetch
git checkout v0.3.0  # or latest version
cd ..
git add kit
git commit -m "[main] Update multiagent kit to v0.3.0"
```

## Structure

```
~/workspaces/
├── kit/                           # this submodule
│   └── skills/
│       ├── multiagent-bootstrap/
│       ├── multiagent-state-manager/
│       ├── multiagent-telegram-setup/
│       └── multiagent-kit-guide/
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
