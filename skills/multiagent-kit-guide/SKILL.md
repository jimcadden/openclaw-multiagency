---
name: multiagent-kit-guide
description: Guide for using and maintaining the openclaw-multiagent kit. Quick reference for updating the kit, adding agents, troubleshooting, and contributing.
---

# Multi-Agent Kit Guide

Quick reference for working with the `openclaw-multiagent` kit.

## Quick Commands

### Update Kit to New Version

Use the interactive updater (recommended):

```bash
{baseDir}/scripts/update-kit.sh
```

Or manually:

```bash
cd kit
git fetch
LATEST=$(git describe --tags --abbrev=0 $(git rev-list --tags --max-count=1))
git checkout "$LATEST"
cd ..
git add kit
git commit -m "[main] Update kit to $LATEST"
```

### Check Kit Status

```bash
cd kit
git status           # See if you're on a tag or branch
git describe --tags  # Show current version
git log --oneline -5 # Recent kit commits
```

### Reset Kit to a Specific Version

```bash
cd kit
git reset --hard <version-tag>
cd ..
git add kit
git commit -m "[main] Reset kit to <version-tag>"
```

## Adding a New Agent

### Option 1: Use add-agent.sh (Recommended)

```bash
cd <workspace>
./kit/scripts/add-agent.sh my-new-agent
```

This handles template copy, skill symlinks, config update, and git commit.

### Option 2: Copy Template (Manual)

```bash
cd <workspace>
cp -r kit/workspace-template my-new-agent

# Edit the files
cd my-new-agent
# Edit IDENTITY.md, USER.md, TOOLS.md

# Add symlinks through shared/
ln -s ../shared/skills/multiagent-state-manager multiagent-state-manager
ln -s ../shared/skills/multiagent-telegram-setup multiagent-telegram-setup
ln -s ../shared/skills/multiagent-kit-guide multiagent-kit-guide
```

### Register in OpenClaw

Edit `<openclaw-dir>/openclaw.json`:

```json
"agents": {
  "list": [
    { "id": "main", "workspace": "<workspace>/main" },
    { "id": "my-new-agent", "workspace": "<workspace>/my-new-agent" }
  ]
}
```

Then restart: `openclaw gateway restart`

## Troubleshooting

### Submodule Issues

**Problem:** `kit/` directory is empty or has errors

```bash
cd <workspace>
git submodule update --init --recursive
```

**Problem:** Kit is on a branch instead of a tag

```bash
cd kit
git checkout <version-tag>  # Pin to stable release
```

### Symlink Issues

**Problem:** Skills not found, broken symlinks

```bash
cd <workspace>/<agent-name>
ls -la multiagent-*  # Check if symlinks resolve

# If broken, recreate (routes through shared/):
rm -f multiagent-state-manager multiagent-telegram-setup multiagent-kit-guide
ln -s ../shared/skills/multiagent-state-manager multiagent-state-manager
ln -s ../shared/skills/multiagent-telegram-setup multiagent-telegram-setup
ln -s ../shared/skills/multiagent-kit-guide multiagent-kit-guide
```

**Problem:** Permission denied on scripts

```bash
chmod +x <workspace>/kit/skills/*/scripts/*.sh
```

### Kit Update Conflicts

**Problem:** Local changes in kit directory

```bash
cd kit
# Option 1: Discard local changes
git reset --hard <version-tag>

# Option 2: Stash and reapply
git stash
git checkout <newer-version-tag>
git stash pop  # May have conflicts to resolve
```

## Contributing to the Kit

### Making Changes

1. **Fork the repo** on GitHub
2. **Clone your fork** as the submodule:
   ```bash
   cd <workspace>
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
# 1. Commit changes
git add -A
git commit -m "Prepare <version>"

# 2. Tag release
git tag -a <version> -m "Release <version> - Description"
git push origin main
git push origin <version>

# 3. Users update via:
# ./multiagent-kit-guide/scripts/update-kit.sh
```

## Directory Reference

```
<workspace>/
├── kit/                           # SUBMODULE - don't edit directly
│   ├── skills/
│   │   ├── multiagent-bootstrap/
│   │   ├── multiagent-state-manager/
│   │   ├── multiagent-telegram-setup/
│   │   └── multiagent-kit-guide/  # ← You are here
│   └── workspace-template/
├── shared/skills/                 # SYMLINKS to kit (single source of truth)
│   ├── multiagent-state-manager  -> ../../kit/skills/multiagent-state-manager
│   ├── multiagent-telegram-setup -> ../../kit/skills/multiagent-telegram-setup
│   └── multiagent-kit-guide      -> ../../kit/skills/multiagent-kit-guide
└── <agent-name>/                  # YOUR AGENT
    ├── IDENTITY.md                # ← Edit this
    ├── USER.md                    # ← Edit this
    ├── MEMORY.md                  # ← Edit this
    ├── multiagent-state-manager  -> ../shared/skills/multiagent-state-manager
    ├── multiagent-telegram-setup -> ../shared/skills/multiagent-telegram-setup
    └── multiagent-kit-guide      -> ../shared/skills/multiagent-kit-guide
```

## Best Practices

1. **Pin to releases** — Don't track `main`, use tagged versions
2. **Commit kit updates** — Always `git add kit && git commit` when updating
3. **Don't edit kit files directly** — Fork and PR, or changes will be lost on update
4. **Use shared/skills/ for reference** — But don't commit there, changes go in kit
5. **Keep agent data in agent dirs** — IDENTITY.md, MEMORY.md, etc. stay with the agent

## Helper Scripts

Scripts are in `{baseDir}/scripts/`:

- `update-kit.sh` — Interactive kit updater
- `check-setup.sh` — Verify workspace health
