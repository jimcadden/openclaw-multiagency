# multiagent-bootstrap

One-time bootstrap for OpenClaw multi-agent workspace.

## Purpose

Sets up the initial `~/agent-workspace/` directory structure, creates the first agent from template, and wires everything into OpenClaw's config.

## When to Run

Once per OpenClaw installation — immediately after OpenClaw is installed and before creating any agents.

## Usage

```bash
cd ~/workspaces
./kit/skills/multiagent-bootstrap/scripts/setup.sh
```

Or if running standalone:

```bash
./setup.sh [agent-name]
```

## What It Does

1. **Validates environment** — checks OpenClaw is installed
2. **Creates workspace structure** — `shared/skills/`, `shared/templates/`
3. **Symlinks shared skills** — wires up `multiagent-state-manager` and `multiagent-telegram-setup`
4. **Creates first agent** — copies workspace-template, prompts for name (default: `main`)
5. **Customizes agent files** — fills in IDENTITY.md, USER.md with user input
6. **Updates openclaw.json** — registers the new agent
7. **Prompts for Telegram** — asks if user wants Telegram setup (default: no)
8. **Initial git commit** — `git add -A && git commit -m "[init] Bootstrap agent workspace"`

## Prerequisites

- OpenClaw installed (`openclaw` CLI available)
- This repo cloned as submodule at `~/agent-workspace/kit/`
- Git initialized in `~/agent-workspace/`

## Files Created

```
~/agent-workspace/
├── kit/                       # this submodule (unchanged)
├── shared/
│   └── skills/
│       ├── multiagent-state-manager -> ../../kit/skills/multiagent-state-manager
│       └── multiagent-telegram-setup -> ../../kit/skills/multiagent-telegram-setup
└── <agent-name>/              # first agent (default: main)
    ├── AGENTS.md
    ├── BOOTSTRAP.md
    ├── HEARTBEAT.md
    ├── IDENTITY.md
    ├── MEMORY.md
    ├── SOUL.md
    ├── TOOLS.md
    ├── USER.md
    ├── multiagent-state-manager -> ../shared/skills/multiagent-state-manager
    └── multiagent-telegram-setup -> ../shared/skills/multiagent-telegram-setup
```

## Post-Bootstrap

1. Restart OpenClaw: `openclaw gateway restart`
2. Verify agent loads: `openclaw status`
3. Run Telegram setup if you didn't: `./kit/skills/multiagent-telegram-setup/scripts/setup-telegram-agent.py`
