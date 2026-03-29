---
name: multiagent-session
description: Session startup protocol. Read this at the start of EVERY session before responding. Detects session type, loads context, checks workspace state.
user-invocable: false
---

# Session Protocol

Do this at the start of every session. Don't ask permission.

## 1. Detect Session Type

Check your system prompt for `SESSION_KEY`. This determines what memory to load.

- **No `SESSION_KEY`**, or key does NOT contain `:topic:` → **Main session.**
- **`SESSION_KEY` contains `:topic:`** → **Forum thread session.**

This is not optional. Check every session.

## 2. Load Memory

**⚠️ You MUST load memory BEFORE responding. No exceptions.**

### Main session (no `:topic:` in key)

```
MEMORY.md            — long-term memory (DO NOT load in group/shared contexts)
```

### Forum thread session (`:topic:` in key)

Do NOT load main `MEMORY.md`. Load this thread's memory instead:

1. **Derive the thread folder** from your `SESSION_KEY`:
   - Replace `:` with `-`
   - Strip the leading `-` from the chat ID segment
   - Example: `agent:main:telegram:bot:group:-1001234567890:topic:123` → `threads/agent-main-telegram-bot-group-1001234567890-topic-123/`

2. **Read the thread memory NOW:**
   ```
   threads/{key}/MEMORY.md         — thread long-term memory (REQUIRED)
   threads/{key}/memory/<today>.md  — daily notes if present (+ yesterday)
   ```

3. **Folder doesn't exist?** New thread — create it. See `shared/skills/multiagent-thread-memory/SKILL.md` for the creation template and end-of-session update protocol.

## 3. Read Your Context

```
SOUL.md              — who you are
USER.md              — who you're helping
memory/<today>.md    — what happened recently (today + yesterday)
HEARTBEAT.md         — pending periodic tasks
```

## 4. Kit Version

Read `.kit-version` in your workspace root and include it in your first response.

## 5. Check Workspace State

Use the `multiagent-state-manager` skill to check for uncommitted changes from the last session. If changes exist, commit them before starting new work.

## 6. Handle Heartbeat Tasks

Read `HEARTBEAT.md`. If any tasks are due, do them now before responding to the user.

## 7. Go

You're ready. Start with what the user needs.

---

_At the end of every session: commit your changes. See `AGENTS.md` for full reference._
