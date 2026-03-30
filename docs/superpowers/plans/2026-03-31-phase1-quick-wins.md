# Phase 1: Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix P0 bugs, make 5 undiscoverable skills discoverable, reclassify 2 internal tools, prune dormant DB tables, and downgrade one over-aggressive validator.

**Architecture:** Pure file edits — no new subsystems. Each task is independent and can be committed separately. Skills get SKILL.md frontmatter following the debugger template pattern. Database schema shrinks by removing unused training tables.

**Tech Stack:** Bash, YAML frontmatter, SQLite schema (ensure-db.sh)

---

### Task 1: Fix PPID collision in deploy-loop-detector.sh

**Files:**
- Modify: `plugin/scripts/validators/deploy-loop-detector.sh:9`

- [ ] **Step 1: Read the current file to confirm the bug location**

Run: `head -15 plugin/scripts/validators/deploy-loop-detector.sh`
Expected: Line 9 shows `DEPLOY_LOG="/tmp/claudetools-deploys-${PPID}.jsonl"`

- [ ] **Step 2: Fix the PPID reference**

Replace line 9:
```bash
# Before:
DEPLOY_LOG="/tmp/claudetools-deploys-${PPID}.jsonl"

# After:
_deploy_session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
_deploy_session_id="${_deploy_session_id:-$$}"
DEPLOY_LOG="/tmp/claudetools-deploys-${_deploy_session_id}.jsonl"
```

The fallback to `$$` (current PID) is safer than `$PPID` because it's at least unique to the hook process. But `session_id` from INPUT is the correct identifier.

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/validators/deploy-loop-detector.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/validators/deploy-loop-detector.sh
git commit -m "fix: use session_id instead of PPID in deploy-loop-detector

PPID is unreliable in hook contexts and collides across parallel
sessions, causing false 'deploy loop' warnings in multi-agent setups."
```

---

### Task 2: Add SKILL.md to claude-code-guide

**Files:**
- Create: `plugin/skills/claude-code-guide/SKILL.md`

Existing files in this skill: 5 validation scripts (`validate-mcp.sh`, `validate-plugin.sh`, `validate-skill.sh`, `validate-hook.sh`, `validate-agent.sh`) + 8 reference guides (`plugins-guide.md`, `skills-guide.md`, `agents-guide.md`, `hooks-guide.md`, `memory-task-guide.md`, `mcp-servers-guide.md`, `prompting-guide.md`, `claude-md-guide.md`).

- [ ] **Step 1: Create SKILL.md**

```yaml
---
name: claude-code-guide
description: >
  Best practices reference for building Claude Code extensions — skills, hooks,
  agents, plugins, slash commands, scripts, MCP servers, CLAUDE.md, memory, and
  task systems. Use when creating, modifying, or troubleshooting any Claude Code
  extension component.
argument-hint: "[topic or question about Claude Code extensions]"
allowed-tools: Glob, Grep, Read, WebFetch, WebSearch
metadata:
  author: claudetools
  version: 1.0.0
  category: development
  tags: [claude-code, plugins, hooks, skills, mcp, reference]
---

# Claude Code Extension Guide

A curated reference for building reliable Claude Code extensions. Routes to the
right guide based on what you are building.

## When to Use

Use this skill when:
- Creating or configuring Claude Code plugins, hooks, skills, or MCP servers
- Writing or testing agent definitions
- Troubleshooting hook behavior or skill loading
- Understanding CLAUDE.md patterns or memory system integration

## Quick Reference

| Building... | Read this reference |
|---|---|
| A skill | `${CLAUDE_SKILL_DIR}/references/skills-guide.md` |
| A hook | `${CLAUDE_SKILL_DIR}/references/hooks-guide.md` |
| An agent | `${CLAUDE_SKILL_DIR}/references/agents-guide.md` |
| Prompts or instructions | `${CLAUDE_SKILL_DIR}/references/prompting-guide.md` |
| CLAUDE.md project instructions | `${CLAUDE_SKILL_DIR}/references/claude-md-guide.md` |
| An MCP server | `${CLAUDE_SKILL_DIR}/references/mcp-servers-guide.md` |
| A plugin | `${CLAUDE_SKILL_DIR}/references/plugins-guide.md` |
| Memory or task integration | `${CLAUDE_SKILL_DIR}/references/memory-task-guide.md` |

## Validation

Run the appropriate validator to check your work:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/validate-skill.sh /path/to/skill-directory
bash ${CLAUDE_SKILL_DIR}/scripts/validate-hook.sh /path/to/hook-script.sh
bash ${CLAUDE_SKILL_DIR}/scripts/validate-agent.sh /path/to/agent.md
bash ${CLAUDE_SKILL_DIR}/scripts/validate-plugin.sh /path/to/plugin-directory
bash ${CLAUDE_SKILL_DIR}/scripts/validate-mcp.sh /path/to/mcp-server-directory
```
```

- [ ] **Step 2: Verify the skill file is valid YAML frontmatter**

Run: `head -15 plugin/skills/claude-code-guide/SKILL.md`
Expected: YAML block with `name: claude-code-guide`

- [ ] **Step 3: Commit**

```bash
git add plugin/skills/claude-code-guide/SKILL.md
git commit -m "feat: add SKILL.md to claude-code-guide skill

Makes the largest skill (6,982 LOC, 8 reference guides, 5 validation
scripts) discoverable via skill invocation. Previously had zero
user-facing entry point."
```

---

### Task 3: Add SKILL.md to code-review

**Files:**
- Create: `plugin/skills/code-review/SKILL.md`

Existing files: `scripts/gather-diff.sh`, `examples/review-output.md`, `references/review-checklist.md`.

- [ ] **Step 1: Create SKILL.md**

```yaml
---
name: code-review
description: >
  Structured 4-pass code review covering correctness, security, performance,
  and maintainability. Use when completing tasks, implementing major features,
  or before merging to verify work meets requirements.
argument-hint: "[file-or-directory-to-review]"
allowed-tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, TodoWrite, WebSearch
metadata:
  author: claudetools
  version: 1.0.0
  category: quality
  tags: [review, quality, security, correctness]
---

# Structured Code Review

4-pass review process: correctness → security → performance → maintainability.

## When to Use

- After completing a major implementation task
- Before merging a feature branch
- When asked to review code quality
- After a subagent finishes work

## Process

1. **Gather context**: Run `bash ${CLAUDE_SKILL_DIR}/scripts/gather-diff.sh` to collect the diff
2. **Pass 1 — Correctness**: Does the code do what it claims? Are edge cases handled?
3. **Pass 2 — Security**: OWASP top 10, injection risks, credential exposure
4. **Pass 3 — Performance**: Unnecessary allocations, N+1 queries, missing indexes
5. **Pass 4 — Maintainability**: Naming, structure, test coverage, documentation

See `${CLAUDE_SKILL_DIR}/references/review-checklist.md` for the full checklist.
See `${CLAUDE_SKILL_DIR}/examples/review-output.md` for example output format.
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/code-review/SKILL.md
git commit -m "feat: add SKILL.md to code-review skill"
```

---

### Task 4: Add SKILL.md to docs-manager

**Files:**
- Create: `plugin/skills/docs-manager/SKILL.md`

Existing files: `scripts/docs-reindex.sh`, `scripts/docs-audit.sh`, `scripts/docs-archive.sh`, `scripts/docs-init.sh`.

- [ ] **Step 1: Create SKILL.md**

```yaml
---
name: docs-manager
description: >
  Manage project documentation with standardized structure, auditing, archiving,
  and index generation. Use when asked to organize docs, check for stale
  documentation, generate a docs index, or set up a docs directory.
argument-hint: "[audit|reindex|archive|init]"
allowed-tools: Glob, Grep, LS, Read, Edit, Write, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: documentation
  tags: [docs, documentation, index, audit, archive]
---

# Documentation Manager

Standardized documentation workflows for project docs directories.

## Commands

| Command | Script | Purpose |
|---------|--------|---------|
| `init` | `${CLAUDE_SKILL_DIR}/scripts/docs-init.sh` | Set up docs/ directory structure |
| `audit` | `${CLAUDE_SKILL_DIR}/scripts/docs-audit.sh` | Check for stale, orphaned, or missing docs |
| `reindex` | `${CLAUDE_SKILL_DIR}/scripts/docs-reindex.sh` | Regenerate docs/index.md from frontmatter |
| `archive` | `${CLAUDE_SKILL_DIR}/scripts/docs-archive.sh` | Move outdated docs to docs/archive/ |
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/docs-manager/SKILL.md
git commit -m "feat: add SKILL.md to docs-manager skill"
```

---

### Task 5: Add SKILL.md to field-review

**Files:**
- Create: `plugin/skills/field-review/SKILL.md`

Existing files: `scripts/collect-metrics.sh`, `scripts/submit-feedback.sh`.

- [ ] **Step 1: Create SKILL.md**

```yaml
---
name: field-review
description: >
  Field review of the claudetools plugin itself (NOT code review). Reports on
  hooks, validators, and skills performance — false positives, bugs, gaps,
  praise. Use when evaluating plugin health or reporting on hook behavior.
argument-hint: "[area-to-review: hooks|validators|skills|all]"
allowed-tools: Glob, Grep, LS, Read, Bash, WebFetch, TodoWrite, WebSearch
metadata:
  author: claudetools
  version: 1.0.0
  category: meta
  tags: [field-review, plugin-health, metrics, feedback]
---

# Field Review

Evaluate claudetools plugin health from real-world usage data.

## When to Use

- After a session with noticeable hook issues (false positives, slowness)
- Periodically to assess plugin health
- When reporting bugs or praise to the plugin maintainer

## Process

1. **Collect metrics**: Run `bash ${CLAUDE_SKILL_DIR}/scripts/collect-metrics.sh`
2. **Review findings**: Analyze hook outcomes, false positive rates, latency
3. **Submit feedback**: Run `bash ${CLAUDE_SKILL_DIR}/scripts/submit-feedback.sh` with findings
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/field-review/SKILL.md
git commit -m "feat: add SKILL.md to field-review skill"
```

---

### Task 6: Add SKILL.md to session-dashboard

**Files:**
- Create: `plugin/skills/session-dashboard/SKILL.md`

Existing files: `scripts/generate-report.sh`.

- [ ] **Step 1: Create SKILL.md**

```yaml
---
name: session-dashboard
description: >
  Generate a human-readable report of claudetools system health, session metrics,
  success rates, failure patterns, and token efficiency. Use when asked for
  session stats, health reports, or plugin metrics.
argument-hint: "[current|summary|all]"
allowed-tools: Glob, Grep, LS, Read, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: observability
  tags: [dashboard, metrics, health, session, report]
---

# Session Dashboard

Generate a report of claudetools system health and session metrics.

## When to Use

- "How is the plugin performing?"
- "Show me session stats"
- "What's the hook success rate?"
- After a long session to review what happened

## Process

Run: `bash ${CLAUDE_SKILL_DIR}/scripts/generate-report.sh`

The report covers:
- Session duration and tool call counts
- Hook decision breakdown (allow/warn/block rates)
- Failure patterns and repeated errors
- Token efficiency metrics
```

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/session-dashboard/SKILL.md
git commit -m "feat: add SKILL.md to session-dashboard skill"
```

---

### Task 7: Reclassify logs/ and memory/ as internal tooling

**Files:**
- Modify: `plugin/skills/logs/` → document as internal
- Modify: `plugin/skills/memory/` → document as internal

These directories contain Python utilities (5 scripts in logs, 2 in memory) that are internal tooling, not user-invocable skills. Rather than moving them (which would break existing references), add a SKILL.md that marks them as internal.

- [ ] **Step 1: Create logs SKILL.md marking it as internal**

```yaml
---
name: logs
description: >
  Extract and query Claude Code session logs — /btw side-questions, conversation
  history, tool usage, errors, and search. Internal utility used by other skills
  and hooks.
argument-hint: "[query|search|btw|errors]"
allowed-tools: Glob, Grep, LS, Read, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: internal
  tags: [logs, session, search, internal]
---

# Session Log Utilities

Query and extract data from Claude Code session logs.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `${CLAUDE_SKILL_DIR}/scripts/extract_btw.py` | Extract /btw side-questions from logs |
| `${CLAUDE_SKILL_DIR}/scripts/search_sessions.py` | Search across session transcripts |
| `${CLAUDE_SKILL_DIR}/scripts/tool_usage.py` | Analyze tool usage patterns |
| `${CLAUDE_SKILL_DIR}/scripts/error_log.py` | Extract and categorize errors |
| `${CLAUDE_SKILL_DIR}/scripts/conversation_history.py` | Browse conversation history |
```

- [ ] **Step 2: Create memory SKILL.md marking it as internal**

```yaml
---
name: memory
description: >
  Manage developer memory — persistent cross-session knowledge. Query, update,
  and maintain the episodic memory system.
argument-hint: "[search|update|consolidate]"
allowed-tools: Glob, Grep, LS, Read, Edit, Write, Bash
metadata:
  author: claudetools
  version: 1.0.0
  category: internal
  tags: [memory, episodic, cross-session, internal]
---

# Memory Management

Manage the persistent cross-session memory system.

## Available Scripts

| Script | Purpose |
|--------|---------|
| `${CLAUDE_SKILL_DIR}/scripts/memory-search.py` | Search memory entries |
| `${CLAUDE_SKILL_DIR}/scripts/memory-update.py` | Update or create memory entries |
```

- [ ] **Step 3: Commit both**

```bash
git add plugin/skills/logs/SKILL.md plugin/skills/memory/SKILL.md
git commit -m "docs: add SKILL.md to logs and memory (internal utilities)"
```

---

### Task 8: Prune dormant training tables from ensure-db.sh

**Files:**
- Modify: `plugin/scripts/lib/ensure-db.sh:238-314`

- [ ] **Step 1: Read the training table section**

Run: `sed -n '230,320p' plugin/scripts/lib/ensure-db.sh`
Expected: 7 CREATE TABLE statements for reference_codebases, prompt_chains, chain_steps, chain_executions, step_executions, deviations, guardrail_gaps

- [ ] **Step 2: Comment out the training tables with a migration note**

Replace lines 238-314 with:

```bash
  # --- Training framework tables (removed from metrics.db) ---
  # These tables were never populated in production. If the safety-evaluator
  # skill needs them, it should create a separate training.db on demand.
  # Removed tables: reference_codebases, prompt_chains, chain_steps,
  # chain_executions, step_executions, deviations, guardrail_gaps
  # Original schema preserved in git history at this commit.
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/lib/ensure-db.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/lib/ensure-db.sh
git commit -m "chore: remove dormant training tables from metrics.db

7 tables (reference_codebases, prompt_chains, chain_steps, etc.)
were created but never populated. Schema preserved in git history.
Safety-evaluator skill can create a separate training.db on demand."
```

---

### Task 9: Downgrade no-deferred-actions from block to warn

**Files:**
- Modify: `plugin/scripts/validators/no-deferred-actions.sh`

This validator has a ~25% false positive rate. It blocks (exit 2) when it detects ≥2 "deferred action" patterns. Downgrading to warn (exit 1) lets the agent see the feedback without being blocked.

- [ ] **Step 1: Read the file to find the exit code**

Run: `grep -n 'return 2\|exit 2' plugin/scripts/validators/no-deferred-actions.sh`
Expected: One or more lines returning exit code 2

- [ ] **Step 2: Change exit/return 2 to exit/return 1**

Replace every `return 2` with `return 1` in the deferred-actions detection path. Keep `return 0` for the clean path unchanged.

Also update the `record_hook_outcome` call to use `"warn"` instead of `"block"`.

- [ ] **Step 3: Verify syntax**

Run: `bash -n plugin/scripts/validators/no-deferred-actions.sh && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/validators/no-deferred-actions.sh
git commit -m "fix: downgrade no-deferred-actions from block to warn

25% false positive rate makes blocking too aggressive. Downgrade to
warn so agents see the feedback without being stopped. Track trigger
rate — if near-zero after skill improvements, delete entirely."
```

---

## Self-Review Checklist

1. **Spec coverage:** All 5 items from Phase 1 covered:
   - ✓ P0 bugs: PPID fix (Task 1). Session-wrap fragility noted in audit but not blocked here — it's a design question (delete vs fix) best resolved in Phase 2.
   - ✓ SKILL.md for 5 skills (Tasks 2-6)
   - ✓ Reclassify 2 internal tools (Task 7)
   - ✓ Prune dormant DB tables (Task 8)
   - ✓ Downgrade aggressive validator (Task 9)

2. **Placeholder scan:** No TBD, TODO, "implement later", or "similar to Task N" found.

3. **Type consistency:** All SKILL.md files follow the same YAML frontmatter schema (name, description, argument-hint, allowed-tools, metadata with author/version/category/tags). All use `${CLAUDE_SKILL_DIR}` for script references.
