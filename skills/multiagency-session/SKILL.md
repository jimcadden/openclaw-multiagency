---
name: multiagency-session
description: Session startup protocol. Read this at the start of EVERY session before responding. Detects session type, loads context, checks workspace state.
user-invocable: false
---

# Session Protocol

Do this at the start of every session. Don't ask permission.

## 1. Detect Session Type

Check your system prompt for `SESSION_KEY`. This determines what memory to load.

- **No `SESSION_KEY`**, or key contains neither `:topic:` nor `:thread:` → **Main session.**
- **`SESSION_KEY` contains `:topic:` or `:thread:`** → **Thread session** (Telegram forum topic, Discord thread, etc.)

This is not optional. Check every session.

## 2. Load Memory

**⚠️ You MUST load memory BEFORE responding. No exceptions.**

### Main session (no `:topic:` or `:thread:` in key)

```
MEMORY.md            — long-term memory (DO NOT load in group/shared contexts)
```

### Thread session (`:topic:` or `:thread:` in key)

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

3. **Folder doesn't exist?** New thread — create it. See `shared/skills/multiagency-thread-memory/SKILL.md` for the creation template and end-of-session update protocol.

## 3. Read Your Context

```
SOUL.md              — who you are
USER.md              — who you're helping
memory/<today>.md    — what happened recently (today + yesterday)
HEARTBEAT.md         — pending periodic tasks
```

## 4. Kit Version

Read `../.kit-version` (one level up from your agent folder, in the shared workspace root where `kit/` lives) and include the version in your first response.

## 5. Check Workspace State

Use the `multiagency-state-manager` skill to check for uncommitted changes from the last session. If changes exist, commit them before starting new work.

## 6. Handle Heartbeat Tasks

Read `HEARTBEAT.md`. If any tasks are due, do them now before responding to the user.

## 7. Go

You're ready. Start with what the user needs.

---

## Session Timeout

Sessions expire after a configurable idle period (`sessions.idleTimeout` in `openclaw.json`, default `7d`). When a session expires, the transcript resets and you start fresh — this is normal.

**What survives:** Your workspace files, thread memory, daily notes, and MEMORY.md are all on disk and unaffected.

**What to do:** Always update your memory files (MEMORY.md or thread MEMORY.md) before going quiet. This is how you preserve context across session boundaries. If you wake up with no transcript history but your memory files have context, a prior session expired — pick up where it left off.

---

_At the end of every session: commit your changes. See `AGENTS.md` for full reference._
