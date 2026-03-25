---
title: "FAQ"
description: "Answers to common questions about installing, using, and troubleshooting claudetools — organized by topic."
sidebar:
  order: 4
---

Answers to common questions, organized by topic.

---

## Installation

### Do I need to configure anything after installing?

No. Run `/plugin install claudetools@claudetools-marketplace` and hooks activate immediately — no config files, no environment variables, no restart required. See [Installation](/marketplace/getting-started/installation/) for requirements (Node.js 18+, SQLite3).

### How do I know the install actually worked?

Run `/session-dashboard` at the end of your first session. You'll see hook fire counts, block rates, and tool success metrics. Zero counts means something didn't load. See [Troubleshooting](/marketplace/advanced/troubleshooting/) if hooks are missing.

### How do I update claudetools?

Run `/plugin update claudetools`. Your data directory (memories, metrics DB) is stored outside the versioned plugin directory and survives upgrades automatically.

### What Node.js version do I need?

Node.js 18 or later. The codebase-pilot indexer runs as a Node.js process, so if Node isn't in PATH when Claude Code launches, indexing will silently fail. See [Troubleshooting — Codebase-Pilot Not Indexing](/marketplace/advanced/troubleshooting/#codebase-pilot-not-indexing).

---

## Daily Usage

### Why did Claude block my command?

A safety hook intercepted it before it ran. The most common trigger is `rm -rf` or similar destructive patterns — the `dangerous-bash` validator blocks these and explains the safe alternative. Safety hooks always run and can't be disabled. See [Core Concepts — Hooks](/marketplace/getting-started/core-concepts/#hooks) for the four hook categories.

### Why are hooks making every tool call slow?

Non-safety hooks add latency on every tool call. Start Claude with `CLAUDE_HOOKS_QUIET=1` to skip all non-critical hooks for sessions where speed matters — safety hooks still run. See [Configuration](/marketplace/advanced/configuration/#claude_hooks_quiet) for details.

### Why does Claude seem to remember things from a previous session?

The memory system injects relevant context from past sessions at startup. Memories above the confidence threshold (default 0.7) are prepended automatically. Run `/memory` to inspect or prune what's stored. See [Configuration — Memory System](/marketplace/advanced/configuration/#memory-system).

### How do I turn off the memory injection?

Raise the `memory_confidence_inject` threshold in `adaptive-weights.sh` or run `/memory prune` to reduce what's stored. You can't disable injection entirely without modifying the hook, but raising the threshold to `1.0` effectively suppresses it. See [Configuration — Adaptive Thresholds](/marketplace/advanced/configuration/#adaptive-thresholds).

### Why is Claude reading files it already read earlier in the session?

The `guard-context-reread` hook blocks redundant reads — if Claude tries to re-read an unchanged file, the hook returns the cached result. If you're seeing the warning, Claude is attempting it and the hook is working as intended. See [Core Concepts — Hooks](/marketplace/getting-started/core-concepts/#hooks).

---

## Skills & Commands

### What's the difference between a skill and a slash command?

Skills auto-trigger when your task matches a pattern — you don't have to invoke them explicitly. Slash commands always require you to type them. For example, `/debugger` fires automatically when you say "this is broken", but `/session-dashboard` only runs when you ask for it. See [Core Concepts — Skills](/marketplace/getting-started/core-concepts/#skills) and [Core Concepts — Slash Commands](/marketplace/getting-started/core-concepts/#slash-commands).

### How do I trigger a skill manually?

Type `/skill-name` in the chat. For example, `/exploring-codebase` starts semantic codebase navigation even if Claude didn't auto-trigger it. All available skills are listed in [Core Concepts — Skills](/marketplace/getting-started/core-concepts/#skills).

### Why did the bug-fixing skill jump straight to a fix without reproducing first?

The `/debugger` skill enforces a 6-step protocol: REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY → FIX → CONFIRM. If Claude skipped steps, it may not have triggered the skill — try invoking `/debugger` explicitly. See the [Debug a Bug guide](/marketplace/guides/debug-a-bug/) for the full protocol.

### What languages does codebase-pilot support?

14 languages: TypeScript, JavaScript, Python, Go, Rust, Java, Kotlin, Ruby, C#, PHP, Swift, C/C++, and Bash. Unsupported files are still readable but won't appear in symbol search or import tracing. See [Codebase Pilot — Supported Languages](/marketplace/reference/codebase-pilot/supported-languages/).

---

## Troubleshooting

### Codebase-pilot can't find a symbol I know exists — why?

The file may not have been indexed yet. Run `node plugin/codebase-pilot/dist/cli.js index-file <path>` for targeted reindexing, or run `node plugin/codebase-pilot/dist/cli.js doctor` to check index health. See [Troubleshooting — Codebase-Pilot Not Indexing](/marketplace/advanced/troubleshooting/#codebase-pilot-not-indexing).

### Hooks are blocking things that seem perfectly fine — how do I reduce false positives?

Run `/field-review` to audit recent hook decisions and reclassify false positives. For persistent over-firing on a specific validator, raise its threshold in `adaptive-weights.sh`. See [Troubleshooting — High Block Rates](/marketplace/advanced/troubleshooting/#high-block-rates).

### I'm getting "database is locked" errors — what do I do?

The metrics DB uses WAL mode with a 5-second busy timeout — concurrent locks from multiple sessions usually self-resolve. If it persists, run `sqlite3 data/metrics.db "PRAGMA wal_checkpoint(TRUNCATE);"`. See [Troubleshooting — Metrics DB Locked](/marketplace/advanced/troubleshooting/#metrics-db-locked).

---

## Related

- [Installation](installation.md) — prerequisites, install steps, and verification
- [Core Concepts](core-concepts.md) — understand hooks, skills, and agents
- [Troubleshooting](/advanced/troubleshooting/) — deeper fixes for hooks, indexing, and DB issues
