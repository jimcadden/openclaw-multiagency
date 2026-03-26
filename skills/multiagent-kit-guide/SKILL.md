---
name: multiagent-kit-guide
description: Guide for using and maintaining the openclaw-multiagent kit. Quick reference for updating the kit, adding agents, troubleshooting, and contributing.
---

# Multi-Agent Kit Guide

Quick reference for working with the `openclaw-multiagent` kit.

## Quick Commands

### Update Kit to New Version

```bash
cd ~/workspaces/kit
git fetch
git checkout v0.2.0  # or latest tag
cd ..
git add kit
git commit -m "[main] Update kit to v0.2.0"
```

### Check Kit Status

```bash
cd ~/workspaces/kit
git status          # See if you're on a tag or branch
git describe --tags # Show current version
git log --oneline -5 # Recent kit commits
```

### Reset Kit to Clean State

```bash
cd ~/workspaces/kit
git reset --hard v0.1.0  # or whatever version you want
cd ..
git add kit
git commit -m "[main] Reset kit to v0.1.0"
```

## Adding a New Agent

### Option 1: Copy Template (Manual)

```bash
cd ~/workspaces
cp -r kit/workspace-template my-new-agent

# Edit the files
cd my-new-agent
vim IDENTITY.md    # Agent name, emoji, vibe
vim USER.md        # Your info
vim TOOLS.md       # Any local tool notes

# Add symlinks to kit skills
ln -s ../kit/skills/multiagent-state-manager multiagent-state-manager
ln -s ../kit/skills/multiagent-telegram-setup multiagent-telegram-setup
```

### Option 2: Use Bootstrap (Fresh Install Only)

If you want a second workspace (not recommended for existing setups):

```bash
mkdir ~/workspaces-v2
cd ~/workspaces-v2
git init
git submodule add https://github.com/jimcadden/openclaw-multiagent.git kit
cd kit && git checkout v0.1.0 && cd ..
./kit/skills/multiagent-bootstrap/scripts/setup.sh my-new-agent
```

### Register in OpenClaw

Edit `~/.openclaw/openclaw.json`:

```json
"agents": {
  "list": [
    { "id": "main", "workspace": "/home/user/workspaces/main" },
    { "id": "my-new-agent", "workspace": "/home/user/workspaces/my-new-agent" }
  ]
}
```

Then restart: `openclaw gateway restart`

## Troubleshooting

### Submodule Issues

**Problem:** `kit/` directory is empty or has errors

```bash
cd ~/workspaces
git submodule update --init --recursive
```

**Problem:** Kit is on a branch instead of a tag

```bash
cd ~/workspaces/kit
git checkout v0.1.0  # Pin to stable release
```

### Symlink Issues

**Problem:** Skills not found, broken symlinks

```bash
cd ~/workspaces/main
ls -la multiagent-*  # Check if symlinks resolve

# If broken, recreate:
rm -f multiagent-state-manager multiagent-telegram-setup
ln -s ../kit/skills/multiagent-state-manager multiagent-state-manager
ln -s ../kit/skills/multiagent-telegram-setup multiagent-telegram-setup
```

**Problem:** Permission denied on scripts

```bash
chmod +x ~/workspaces/kit/skills/*/scripts/*.sh
```

### Kit Update Conflicts

**Problem:** Local changes in kit directory

```bash
cd ~/workspaces/kit
# Option 1: Discard local changes
git reset --hard v0.1.0

# Option 2: Stash and reapply
git stash
git checkout v0.2.0
git stash pop  # May have conflicts to resolve
```

## Contributing to the Kit

### Making Changes

1. **Fork the repo** on GitHub
2. **Clone your fork** as the submodule:
   ```bash
   cd ~/workspaces
   rm -rf kit
   git submodule add https://github.com/YOURNAME/openclaw-multiagent.git kit
   cd kit && git checkout -b my-feature
   ```
3. **Make changes** in `kit/skills/`
4. **Test locally** before committing
5. **Push and PR** to upstream

### Release Process

For maintainers:

```bash
# 1. Update version references in docs
vim README.md  # Update any version strings

# 2. Commit changes
git add -A
git commit -m "[main] Prepare v0.2.0"

# 3. Tag release
git tag -a v0.2.0 -m "Release v0.2.0 - Description"
git push origin main
git push origin v0.2.0

# 4. Users can now update:
# cd ~/workspaces/kit && git fetch && git checkout v0.2.0
```

## Directory Reference

```
~/workspaces/
├── kit/                           # SUBMODULE - don't edit directly
│   ├── skills/
│   │   ├── multiagent-bootstrap/
│   │   ├── multiagent-state-manager/
│   │   ├── multiagent-telegram-setup/
│   │   └── multiagent-kit-guide/  # ← You are here
│   └── workspace-template/
├── shared/skills/                 # SYMLINKS to kit
│   ├── multiagent-state-manager -> ../../kit/...
│   └── multiagent-telegram-setup -> ../../kit/...
└── main/                          # YOUR AGENT
    ├── IDENTITY.md                # ← Edit this
    ├── USER.md                    # ← Edit this
    ├── MEMORY.md                  # ← Edit this
    ├── multiagent-state-manager -> ../kit/...
    └── multiagent-telegram-setup -> ../kit/...
```

## Best Practices

1. **Pin to releases** — Don't track `main`, use tagged versions
2. **Commit kit updates** — Always `git add kit && git commit` when updating
3. **Don't edit kit files directly** — Fork and PR, or changes will be lost on update
4. **Use shared/skills/ for reference** — But don't commit there, changes go in kit
5. **Keep agent data in agent dirs** — IDENTITY.md, MEMORY.md, etc. stay with the agent

## Helper Scripts

This skill includes helper scripts in `scripts/`:

- `update-kit.sh` — Interactive kit updater
- `check-setup.sh` — Verify workspace health

See individual scripts for usage.
