---
name: multiagency-thread-memory
description: Thread memory protocol for persistent thread sessions (Telegram forum topics, Discord threads, etc.). Load this skill at the start of any session where SESSION_KEY contains :topic: or :thread: — i.e., you are in a long-running thread with its own session context.
user-invocable: false
---

# Thread Memory Protocol

You are in a persistent thread session (Telegram forum topic, Discord thread, or similar). Each thread is a separate long-running conversation with its own persistent memory. Follow this protocol now.

> **Why this matters:** Sessions expire after an idle timeout (`sessions.idleTimeout` in `openclaw.json`, default `7d`). When that happens, your transcript resets and you lose all conversational context. Thread memory is the bridge — it survives session expiry and lets you pick up where you left off.

## Step 1 — Derive Your Thread Folder

Your session key was injected into your system prompt:
```
SESSION_KEY: agent:main:telegram:mybot:group:-1001234567890:topic:123
```

Sanitize it into a folder name: replace `:` with `-`, strip any leading `-` from the chat ID.

```
agent:main:telegram:mybot:group:-1001234567890:topic:123
→ threads/agent-main-telegram-mybot-group-1001234567890-topic-123/
```

## Step 2 — Load Thread Memory

Check if the folder exists:

**Folder exists:**
```
threads/{key}/MEMORY.md        — read this (thread long-term memory)
threads/{key}/memory/<today>.md  — read if present (yesterday's too)
```

**Folder does not exist → new thread.** Create it now (see below), then respond.

## Step 3 — Respond

You are now oriented to this thread's full history. Respond accordingly.

## Step 4 — Update Memory Before Going Quiet

At the end of the session:
1. Update `threads/{key}/MEMORY.md` with new context, decisions, open questions
2. Optionally write `threads/{key}/memory/YYYY-MM-DD.md` for raw session notes
3. Commit with `multiagency-state-manager`

---

## Creating a New Thread

```bash
mkdir threads/{sanitized-session-key}
```

Create `threads/{key}/MEMORY.md`:

```markdown
# Thread: {Topic Name}

## Session Key
{Full session key — e.g., agent:main:telegram:mybot:group:-1001234567890:topic:123}

## Topic
{Telegram topic name as it appears in the chat}

## Purpose
{What this thread is for}

## Context
{Key background, current state, what we're working on}

## Key Facts & Decisions
{Important things to remember across sessions}

## Open Threads
{Unresolved questions, pending follow-ups}

## History
{Timeline of significant milestones}
```

Commit the new folder before continuing.

---

## Notes

- **Persistent threads only.** Telegram forum topics (`:topic:` in session key) and Discord threads (`:thread:` in session key) get their own memory. Regular Telegram groups without topics share one session and have no thread memory.
- **Don't cross-contaminate.** Thread memory is thread-specific. Never load another thread's memory or your main `MEMORY.md` here.
- **Session key is stable.** Thread IDs don't change, so the folder name is permanent.
- **Sessions expire.** After `sessions.idleTimeout` (default `7d`) of inactivity, OpenClaw resets the transcript. Your thread memory files on disk are unaffected — always update them before going quiet so you can recover on the next session.
