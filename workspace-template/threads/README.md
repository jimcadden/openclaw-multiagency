# threads/ - Thread Memory

This directory holds long-term memory for persistent thread sessions — Telegram forum topics, Discord threads, or any channel where OpenClaw assigns a stable per-thread session key. Each thread gets its own subfolder named after its **session key**.

## Why This Exists

Channels like Telegram forum supergroups and Discord servers can have multiple concurrent threads — one about hobbies, one about health, one about a project, etc. Each thread gets its own unique session key in OpenClaw, with its own JSONL transcript. But transcripts have two limits:

1. **Context window** — old messages eventually fall off as the transcript grows
2. **Session timeout** — after a period of inactivity (configured via `session.idleMinutes` in `openclaw.json`, default `10080` — 7 days), the session expires and the transcript resets entirely

Thread memory files solve both problems. At the start of each thread session, the agent's system prompt includes its session key. The agent uses that key directly to find and load its thread memory — no guessing, no fuzzy matching. Even if the session expired overnight or over a weekend, the agent reloads its thread memory and picks up where it left off.

> **Note:** For Telegram, this only applies to **forum supergroups** (Topics must be enabled in group settings). Regular Telegram groups with reply threads share one session key — their reply threads are not persistent topic sessions and do not get separate memory.

## Directory Structure

```
threads/
  README.md                                                         ← you are here
  agent-main-telegram-mybot-group-1001234567890-topic-123/          ← Telegram forum topic
    MEMORY.md                                                       ← thread long-term memory
    memory/
      YYYY-MM-DD.md                                                 ← daily session notes (optional)
  agent-main-telegram-mybot-group-1001234567890-topic-456/
    MEMORY.md
  agent-main-discord-channel-1489699841322909786/                                ← Discord channel/thread
    MEMORY.md
```

## Folder Naming

The folder name is the **sanitized session key** from the system prompt:

**Telegram forum topic:**
```
SESSION_KEY: agent:main:telegram:mybot:group:-1001234567890:topic:123
          ↓  replace : with -, strip leading - from chat ID
folder: agent-main-telegram-mybot-group-1001234567890-topic-123
```

**Discord channel/thread:**
```
SESSION_KEY: agent:main:discord:channel:1489699841322909786
          ↓  replace : with -
folder: agent-main-discord-channel-1489699841322909786
```

This makes the mapping from session → memory file completely deterministic.

## Thread MEMORY.md Template

When creating a new thread folder, use this template for its `MEMORY.md`:

```markdown
# Thread: {Topic Name}

## Session Key
{Full session key — e.g., agent:main:telegram:mybot:group:-1001234567890:topic:123 or agent:main:discord:channel:1489699841322909786}

## Topic
{The topic/thread name as it appears in the chat}

## Purpose
{What this thread is for — the ongoing subject of this conversation}

## Context
{Key background information, current state, what we're actively working on}

## Key Facts & Decisions
{Important things to remember across sessions — facts established, decisions made}

## Open Threads
{Unresolved questions, pending follow-ups, things we plan to revisit}

## History
{Brief timeline of significant milestones, major developments, notable moments}
```

## Protocol

**Session start:**
1. Get session key from system prompt (`SESSION_KEY: ...`)
2. Sanitize: replace `:` with `-`, strip leading `-` from chat ID
3. Read `threads/{session-key}/MEMORY.md`
4. Optionally read `threads/{session-key}/memory/<today>.md` and `<yesterday>.md`

**Session end:**
1. Update `threads/{session-key}/MEMORY.md` with new context
2. Optionally write `threads/{session-key}/memory/YYYY-MM-DD.md` for raw session notes
3. Commit with `multiagency-state-manager`

## Session Timeout

OpenClaw sessions expire after a configurable idle period. The multiagency kit defaults to `10080` minutes (7 days), set via `session.idleMinutes` in `openclaw.json`. When a session expires:

- The JSONL transcript resets — the agent has no conversational history
- Thread memory files in this directory are **not affected** — they persist on disk
- On the next message, the agent starts a new session, loads its thread memory, and continues

This is why updating `MEMORY.md` at the end of every session is critical: it's the bridge that survives session expiry.

To check or change the timeout:

```json
// ~/.openclaw/openclaw.json
"session": {
  "idleMinutes": 10080
}
```

See `shared/skills/multiagency-thread-memory/SKILL.md` for the full Thread Memory Protocol.
