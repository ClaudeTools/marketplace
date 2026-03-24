---
title: "Context Hooks"
description: "Hooks that manage session context — project state injection at startup, file read tracking, memory indexing, and source reindexing on edit."
---
Hooks that manage session context — injecting project state at startup, tracking file reads and edits, maintaining the memory index, and triggering reindexing when source files change.

## What this protects you from

Context hooks prevent Claude from starting each session blind. Without them, every conversation would begin with no knowledge of what tasks are in progress, what files were recently changed, or whether another agent is working in the same repo. These hooks automatically inject relevant state at session start and keep the project index up to date as files change — so Claude's answers stay accurate throughout the session without you having to re-explain the situation.

---

## inject-session-context

**Event:** SessionStart
**Script:** `scripts/inject-session-context.sh`

Runs at the start of every session. Injects relevant project state into the context:
- Active tasks from `.tasks/`
- Recent git activity (last 5 commits)
- Agent mesh status (other active agents)
- Current worktree branch and status

Ensures the agent starts with an accurate picture of where work left off.

---

## inject-prompt-context

**Event:** UserPromptSubmit
**Script:** `scripts/inject-prompt-context.sh`

Runs on every user prompt. Injects lightweight context relevant to the prompt:
- Memory preferences (ALWAYS/NEVER constraints)
- Active task state
- Any pending mesh messages

Keeps context fresh without loading everything at session start.

---

## track-file-reads

**Event:** PostToolUse (Read)
**Script:** `scripts/track-file-reads.sh`

Records every file that has been read in the current session. Used by:
- `pre-edit-gate.sh` to detect blind edits (editing without reading)
- `guard-context-reread.sh` to block redundant re-reads
- Telemetry for token efficiency analysis

---

## track-file-edits

**Event:** PostToolUse (Edit, Write)
**Script:** `scripts/track-file-edits.sh`

Records every file that has been edited in the session. Used by:
- `edit-frequency-guard.sh` to detect churn
- `enforce-git-commits.sh` to detect uncommitted work
- Task `files_touched` tracking

---

## memory-index / memory-extract-fast / memory-reflect

**Events:** PostToolUse (Edit, Write), Stop
**Scripts:** `scripts/memory-index.sh`, `scripts/memory-extract-fast.sh`, `scripts/memory-reflect.sh`

The memory pipeline:
- `memory-index.sh` — updates the memory index after each file edit, tracking what changed
- `memory-extract-fast.sh` — runs at session stop; extracts patterns, preferences, and decisions from the session for memory persistence
- `memory-reflect.sh` — reflects on session outcomes to update generated memory context

---

## reindex-on-edit

**Event:** PostToolUse (Edit, Write)
**Script:** `scripts/reindex-on-edit.sh`

Triggers the codebase-pilot incremental reindex (`index-file`) whenever a source file is edited. Keeps the symbol index current so subsequent `find-symbol` and `file-overview` calls reflect the latest code.

---

## guard-context-reread

**Event:** PreToolUse (Read)
**Script:** `scripts/guard-context-reread.sh`

Blocks re-reading a file that is already in context and has not changed since the last read. When triggered, it suggests using `offset`/`limit` parameters to read a specific section instead.

Prevents the most common form of token waste in long sessions.

---

## archive-before-compact / restore-after-compact

**Events:** PreCompact, PostCompact
**Scripts:** `scripts/archive-before-compact.sh`, `scripts/restore-after-compact.sh`

Run before and after context compaction:
- `archive-before-compact.sh` — saves critical session state (active tasks, file read list, mesh registrations) to disk before compaction discards it
- `restore-after-compact.sh` — reloads the saved state after compaction so the session continues without losing context
