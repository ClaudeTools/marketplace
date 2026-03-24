---
title: "What's New"
description: "Release history for claudetools — recent versions with features, improvements, and bug fixes."
sidebar:
  order: 1
---

Release notes for the claudetools plugin. Versions follow [semantic versioning](https://semver.org/) — `feat:` bumps minor, `fix:`/`chore:` bumps patch, breaking changes bump major.

---

## 4.0.0 — 2026-03-24

**Breaking change:** Plugin restructured to align with the canonical `.claude/` folder anatomy. Slash commands moved from skills to native command format.

### Features

- **8 native slash commands** in `commands/` with `$ARGUMENTS` and backtick support: `/claude-code-guide`, `/code-review`, `/docs-manager`, `/field-review`, `/logs`, `/memory`, `/mesh`, `/session-dashboard`
- **4 new rule files** that replace hook-injected behavioral instructions:
  - `rules/project-tooling.md` — project type → build/test/lint command table
  - `rules/memory-discipline.md` — standing instruction to save learnings after sessions
  - `rules/memory-enforcement.md` — check MEMORY.md before acting
  - `rules/session-orientation.md` — churn and failure awareness guidance

### Improvements

- `enforce-task-quality.sh` refactored to delegate to `validators/task-quality.sh` — single source of truth
- `memory-reflect.sh` consolidated with `session-learn-negatives.sh` — two phases in one Stop hook instead of three scripts
- `inject-session-context.sh` now queries the failure-pattern DB for learned patterns (migrated from dynamic-rules.sh)
- `test-writer` agent gains `disallowedTools: [Write]` to prevent arbitrary file creation
- `frontend-design` and `improve` skills now have complete frontmatter (were broken stubs)

### Migration

Slash commands previously invoked as `/claudetools:name` are now `/project:name` (native command format). All behavioral enforcement is preserved — delivery mechanism changed from hook stdout to `rules/` files. No action required for existing users.

---

## 3.1.0 — 2026-03-16

### Features

- **Documentation management system** — 3 hooks + 1 skill:
  - `doc-manager.sh` (PostToolUse) — enforces kebab-case naming, YAML frontmatter, auto-updates modified dates
  - `doc-index-generator.sh` (SessionEnd, async) — regenerates `index.md` in all `docs/` directories
  - `doc-stale-detector.sh` (SessionStart) — warns about stale (>90 days) and deprecated docs
  - [`/docs-manager`](commands/docs-manager.md) skill — `init`, `audit`, `archive`, `reindex` commands
- **Training infrastructure** — 986-command safety corpus (102 dangerous, 534 safe, 284 boundary) with headless runner, cross-model comparison, and continuous training loop
- **Adaptive weights system** — 17 DB-driven thresholds with per-hook outcome recording, cost-sensitive gradient descent, per-model multipliers (Opus/Sonnet/Haiku), and full audit trail
- [`/train`](commands/session-dashboard.md) skill — `test`, `code`, `noncode`, `edge`, `headless`, `compare-models`, `cross-model`, `all`

### Bug Fixes

- PPID isolation: `failure-pattern-detector.sh` uses `session_id` from hook JSON instead of unreliable PPID
- `enforce-team-usage.sh` uses `jq` instead of `python3` for settings.json reads
- `block-dangerous-bash.sh` catches 17 additional dangerous commands (mkfs, fdisk, wipefs, reverse shells, `chmod -R 777`, `wget | sh`, `git push -f`, PATH clearing)
- Metrics DB fragmentation resolved — single canonical `data/metrics.db`
- Session ID propagation fixed in `record_hook_outcome`

---

## 3.0.0 — 2026-03-15

**Major release:** 7 new hook event types, self-learning layer, 4 new skills, 4 new agents.

### Features

- **7 new hook event types** — UserPromptSubmit, PermissionRequest, PostToolUseFailure, PreCompact, PostCompact, Notification, ConfigChange, InstructionsLoaded
- **Self-learning layer:**
  - `metrics.db` — SQLite with tool_outcomes, session_metrics, threshold_overrides tables
  - `capture-outcome.sh` — PostToolUse telemetry for every tool call
  - `aggregate-session.sh` — SessionEnd metrics (edit churn, failure rate, task velocity)
  - `inject-session-context.sh` — SessionStart injection of learned patterns
  - Adaptive thresholds — safety-bounded [0.5×, 2.0×] tuning from session data (removed in later versions)
- **4 new skills:** [`/code-review`](commands/code-review.md), `/investigating-bugs`, `/tune-thresholds`, [`/session-dashboard`](commands/session-dashboard.md)
- **4 new agents:** [code-reviewer](agents/code-reviewer.md), [test-writer](agents/test-writer.md), [researcher](agents/researcher.md), [architect](agents/architect.md)
- `auto-approve-safe.sh` — auto-approves read-only tools and test/lint/typecheck commands across 8 languages
- `desktop-alert.sh` — macOS/Linux desktop alerts for permission prompts and idle agents
- `config-audit-trail.sh` — logs all configuration changes to JSONL

### Bug Fixes

- SQL injection — fixed unescaped string interpolation in sqlite3 queries
- Multi-language stub detection — now covers Python, Rust, Go, Java, C#, Ruby (was TypeScript-only)
- Race condition — `edit-frequency-guard.sh` uses `flock` for atomic counter updates
- `guard-sensitive-files.sh` distinguishes Read (allowed for `.env`) from Edit/Write (blocked)

---

## 2.0.0 — 2026-03-15

### Features

- 30 hooks across 9 lifecycle events — full enforcement coverage
- 4 Haiku-powered prompt hooks: research-before-writing, deterministic-tools, completion-audit, session-quality-audit
- **Codebase-pilot** — tree-sitter + SQLite semantic index with 5 MCP tools: `project_map`, `find_symbol`, `find_usages`, `file_overview`, `related_files`
- `enforce-codebase-pilot` hook — redirects grep/search to the semantic index for known symbols
- `stop_hook_active` guard — prevents infinite loops in Stop event hooks
- `verify-subagent-independently` — independent verification of subagent work at SubagentStop
- `enforce-team-usage` — blocks bare Agent spawning without TeamCreate
- `require-active-task` — blocks writes without an active task
- `edit-frequency-guard` — detects excessive same-file edits (rewrite signal)
- `block-unasked-restructure` — prevents unrequested project restructuring
- `check-mock-in-prod` — flags mock/hardcoded data in production code
- `session-stop-gate` — comprehensive session review before exit
- `prompt-improver` v5.0.0 — self-contained guardrails burned into every generated prompt

---

## Related

- [Installation](../getting-started/installation.md) — get the latest version
- [Cheat Sheet](cheat-sheet.md) — all commands and hooks at a glance
- [CHANGELOG](https://github.com/ClaudeTools/marketplace/blob/main/claudetools/CHANGELOG.md) — full history on GitHub
