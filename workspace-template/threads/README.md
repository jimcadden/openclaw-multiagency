# threads/ - Telegram Forum Thread Memory

This directory holds long-term memory for each Telegram forum topic thread. Each thread gets its own subfolder named after its **session key** — the stable, unique identifier OpenClaw assigns to that topic.

## Why This Exists

In Telegram, a **forum supergroup** can have multiple topic threads — one about hobbies, one about health, one about a project, etc. Each topic gets its own unique session key in OpenClaw (ending in `:topic:{id}`), with its own JSONL transcript. But the transcript has a context window limit: old messages eventually fall off.

Thread memory files solve this. At the start of each thread session, the agent's system prompt includes its session key. The agent uses that key directly to find and load its thread memory — no guessing, no fuzzy matching.

> **Note:** This only applies to Telegram **forum supergroups** (Topics must be enabled in group settings). Regular Telegram groups with reply threads share one session key — their reply threads are not persistent topic sessions and do not get separate memory.

## Directory Structure

```
threads/
  README.md                                                         ← you are here
  agent-main-telegram-mybot-group-1001234567890-topic-123/
    MEMORY.md                                                       ← thread long-term memory
    memory/
      YYYY-MM-DD.md                                                 ← daily session notes (optional)
  agent-main-telegram-mybot-group-1001234567890-topic-456/
    MEMORY.md
```

## Folder Naming

The folder name is the **sanitized session key** from the system prompt:

```
SESSION_KEY: agent:main:telegram:mybot:group:-1001234567890:topic:123
          ↓  replace : with -, strip leading - from chat ID
folder: agent-main-telegram-mybot-group-1001234567890-topic-123
```

This makes the mapping from session → memory file completely deterministic.

## Thread MEMORY.md Template

When creating a new thread folder, use this template for its `MEMORY.md`:

```markdown
# Thread: {Topic Name}

## Session Key
{Full session key — e.g., agent:main:telegram:mybot:group:-1001234567890:topic:123}

## Topic
{The Telegram topic name as it appears in the chat}

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
3. Commit with `multiagent-state-manager`

See `shared/skills/multiagent-thread-memory/SKILL.md` for the full Thread Memory Protocol.
