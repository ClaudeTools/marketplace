---
title: "Rules"
description: "File-type-scoped behavioral rules injected into the system prompt — how rules work, where they live, and how to write custom rules."
---
Rules are markdown files injected into the system prompt when Claude is working on matching file types. They provide persistent behavioral guidance without consuming context when irrelevant.

Rules live in `plugin/rules/`. The `paths` field in each file's front matter controls which file globs trigger injection.

---

## All 10 Rules

### 1. codebase-navigation

**File:** `codebase-navigation.md`
**Paths:** `**/*.ts`, `**/*.tsx`, `**/*.js`, `**/*.jsx`, `**/*.py`, `**/*.rs`, `**/*.go`, `**/*.java`, `**/*.rb`

Full codebase-pilot CLI command reference table. Injected when working on source code files. Enforces: always use `find-symbol` / `navigate` to locate code before reading files directly. Never guess file paths.

---

### 2. debugging-discipline

**File:** `debugging-discipline.md`
**Paths:** `**/*`

Enforces evidence-based debugging: REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY → FIX → CONFIRM. Activates the two-strike rule (stop after 2 failed attempts, add diagnostic logging, restart from evidence). Requires searching external docs before writing code that calls APIs or external services.

---

### 3. deterministic-over-ai

**File:** `deterministic-over-ai.md`
**Paths:** `**/*`

One principle: if a shell command, script, linter, type-checker, build tool, or test runner can do it — use that. AI inference only for what requires judgment. Includes explicit lists of when to use deterministic tooling vs AI, and what never to do (e.g., never use AI to count files — use `wc`).

---

### 4. memory-awareness

**File:** `memory-awareness.md`
**Paths:** `**/*`

Save learnings to `memory/` when discovering project patterns, user preferences, or making significant decisions. Before writing code, check `MEMORY.md` for `ALWAYS` or `NEVER` constraints. If a planned action contradicts a stored preference, re-read the relevant memory file before proceeding.

---

### 5. no-shortcuts

**File:** `no-shortcuts.md`
**Paths:** `**/*`

No stubs, TODOs, placeholders, or `throw new Error('Not implemented')`. No `as any` abuse or `@ts-ignore`. No mocks outside test files. After writing code, re-read the file to confirm real logic exists. After fixing a bug, demonstrate with real output. Only modify files directly related to the current request.

---

### 6. project-tooling

**File:** `project-tooling.md`
**Paths:** `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, source files

Detect project type from config files and use the correct typecheck/test/lint commands. Tables for TypeScript, Rust, Python, Go. Run typecheck after each change. Run tests before committing.

---

### 7. session-orientation

**File:** `session-orientation.md`
**Paths:** `**/*`

At session start: when edit churn from recent sessions is high, prioritize diagnostics before editing. When failure rate is elevated, research before implementing. Review active tasks and in-progress work before starting new work.

---

### 8. task-management

**File:** `task-management.md`
**Paths:** `**/*`

On session start: check `.tasks/progress.md` and `.tasks/task-manager.json`. During work: use TodoWrite normally (hook persists changes). On session end: run `/task-manager handoff`, commit `.tasks/` to version control.

---

### 9. ui-verification

**File:** `ui-verification.md`
**Paths:** `**/*.tsx`, `**/*.jsx`, `**/*.css`, `**/*.html`, `**/*.vue`, `**/*.svelte`

All UI/UX changes must be verified in Chrome after deployment. Never claim UI work is done without seeing it render with real data. Test at 375px, 768px, and 1440px if responsiveness was changed. Fix issues in Chrome before declaring done.

---

### 10. use-teams

**File:** `use-teams.md`
**Paths:** `**/*`

When `TeamCreate` is available: all multi-task implementation work must use it. Agent tool without team_name is only for quick read-only exploration. When `TeamCreate` is not available: use Agent tool directly with parallel calls for independent work. All work items must be tracked with TaskCreate before starting. Commit after each completed task. Never end a session with uncommitted changes.

---

## Related

- [Core Concepts — Rules](/getting-started/core-concepts/#rules) — how rules differ from hooks and when each is used
- [Advanced: Configuration](/advanced/configuration/) — configure rules paths and injection behavior
- [Reference: Hooks](/reference/hooks/) — hooks enforce specific tool calls; rules govern general behavior