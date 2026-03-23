---
name: claude-code-guide
description: Best practices reference for building Claude Code extensions — skills, hooks, agents, slash commands, scripts, MCP servers, CLAUDE.md, memory, and task systems. Use when creating, reviewing, or debugging any Claude Code extension component.
argument-hint: "[what you're building: skill | hook | agent | script | mcp-server | claude-md]"
---

# Claude Code Extension Guide

A curated reference for building reliable Claude Code extensions. This skill routes you to the right guide based on what you are building, and provides universal principles that apply across all extension types.

## What are you building?

Read the argument the user provided (or infer from context) and load only the relevant reference files — do not load all references at once.

| Building... | Read this |
|---|---|
| A skill (SKILL.md + resources) | `references/skills-guide.md` |
| A hook (hooks.json + shell scripts) | `references/hooks-guide.md` |
| An agent definition (.md in agents/) | `references/agents-guide.md` |
| Prompts or instructions for Claude | `references/prompting-guide.md` |
| CLAUDE.md project instructions | `references/claude-md-guide.md` |
| An MCP server | `references/mcp-servers-guide.md` |
| Memory or task system integration | `references/memory-task-guide.md` |

If the user's intent spans multiple types (e.g., "build a skill with hooks"), load both relevant references.

If the user says something generic like "how do extensions work" or "help me build a plugin", start with this file's universal principles below, then ask what they want to build.

---

## Universal Principles

These apply to every extension type in this plugin.

### 1. File Organization

All source code lives in `plugin/`. The `plugins/` directory contains publishable copies synced by CI — NEVER edit files in `plugins/` directly. Changes go to `plugin/` and get synced via rsync.

```
plugin/
  hooks/hooks.json        — hook configuration
  scripts/                — hook scripts, validators, libraries
  scripts/lib/            — shared libraries (hook-input.sh, worktree.sh)
  scripts/validators/     — single-purpose validator functions
  skills/                 — skill definitions (SKILL.md + resources)
  agents/                 — agent definitions (.md files)
  codebase-pilot/         — code navigation system
  agent-mesh/             — multi-agent coordination
```

### 2. Conventional Commits

All commits must use conventional commit format. CI auto-version uses these to determine version bumps:

- `feat:` — bumps minor version
- `fix:` / `chore:` — bumps patch version
- `!` suffix or `BREAKING CHANGE` footer — bumps major version

NEVER change version numbers manually. The `auto-version.sh` CI script handles all versioning on push to main.

### 3. Shell Script Standards

Every shell script must follow these patterns:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# For hook scripts: consume stdin FIRST, before anything else
source "$SCRIPT_DIR/lib/hook-input.sh"
hook_init
```

Why `set -euo pipefail`: `-e` exits on error, `-u` catches undefined variables, `-o pipefail` catches failures in piped commands. Without these, scripts silently swallow errors.

Why stdin first: Claude Code sends hook data as JSON on stdin. If any sourced library or command reads stdin before `hook_init`, the hook data is lost. This is the single most common hook bug.

### 4. JSON Protocol

Hooks communicate with Claude Code via JSON on stdin and stdout:

- **Input**: JSON object on stdin with fields like `.tool_input`, `.tool_name`, `.session_id`, `.cwd`
- **Output (PreToolUse)**: JSON with `hookSpecificOutput.permissionDecision` (`allow`/`block`) on stdout
- **Output (Stop)**: Findings on stderr, exit code determines behavior
- **Warnings**: JSON with `systemMessage` field on stdout

### 5. Exit Code Contract

| Exit code | Meaning | Behavior |
|---|---|---|
| 0 | Allow | Tool use proceeds normally |
| 1 | Warn | Message shown to agent (stderr for Stop hooks, systemMessage JSON for PreToolUse) |
| 2 | Block | Tool use is prevented (PreToolUse) or turn continues (Stop) |

### 6. Graceful Degradation

Always guard external tool calls. Hooks run in environments where tools may not be installed:

```bash
# Good: guard with existence check
command -v jq &>/dev/null || { echo "jq not found" >&2; exit 0; }

# Good: suppress errors on optional operations
sqlite3 "$DB" "INSERT ..." 2>/dev/null || true

# Bad: assume tool exists
jq '.field' <<< "$INPUT"   # crashes if jq missing
```

External failures must never block the user's workflow. If a non-critical operation fails, log it and continue.

### 7. Performance

Hook scripts must complete quickly:

- **Synchronous hooks**: Target under 100ms. Claude Code waits for these before proceeding.
- **Async hooks** (`"async": true` in hooks.json): Can take longer (up to timeout), but still aim for efficiency.
- **Expensive operations**: Use the `async` flag or defer to background processes.

Avoid unnecessary file I/O, network calls, or subprocess spawning in hot-path hooks like PreToolUse.

### 8. Testing

- **Shell hooks**: Test with BATS (`bats tests/bats/hooks/`)
- **TypeScript**: Test with Vitest (`cd tests && npm test`)
- **Syntax check all scripts**: `for f in plugin/scripts/**/*.sh; do bash -n "$f"; done`
- **Run targeted tests only** — do not run the full suite unless validating a release

### 9. Worktree Awareness

When scripts need the repository root, use `get_repo_root` from `lib/worktree.sh`, not `$(pwd)` or `git rev-parse --show-toplevel`. In worktrees, `pwd` returns the worktree path, not the main repo root. The library handles both cases correctly.

```bash
source "$SCRIPT_DIR/lib/worktree.sh"
local PROJECT_ROOT
PROJECT_ROOT=$(get_repo_root)
```

### 10. Session Identity

Use `get_session_id` from `lib/worktree.sh` to identify the current session. The fallback chain is: hook input `.session_id` > `$SESSION_ID` env var > `$PPID`. NEVER use `$PPID` directly as a session identifier — it is unreliable across different invocation contexts.

---

## Common Gotchas

These span multiple extension types. Each type-specific guide has additional gotchas.

1. **Stop vs SessionEnd**: The `Stop` hook fires at the end of every turn where the agent would stop responding. It does NOT mean the session is closing. Use `SessionEnd` for cleanup that should happen once when the session truly ends.

2. **PPID is not session ID**: `$PPID` changes depending on how the hook is invoked. Always use `get_session_id` from `lib/worktree.sh`, which reads `.session_id` from the hook input JSON first.

3. **Worktree paths**: `$(pwd)` and `git rev-parse --show-toplevel` return the worktree directory when running inside a worktree, not the main repo root. Use `get_repo_root` from `lib/worktree.sh`.

4. **Stdin consumption order**: Hook scripts MUST call `hook_init` (which reads stdin) before sourcing any library that might read from stdin. Move `source lib/hook-input.sh && hook_init` to the very top of the script, before any other sourcing.

5. **Exit code semantics vary by hook type**: In `PreToolUse`, exit 0 always — communicate block/allow via JSON stdout. In `Stop`, the exit code itself is the signal (0=allow, 1=warn, 2=block).

6. **Matcher is a regex**: The `matcher` field in hooks.json is a regular expression, not a simple string. `"matcher": "Read|Edit|Write"` matches any of those three tools. An absent matcher matches all tools for that event.

7. **Hook timeout default**: If no `timeout` is specified, hooks have a default timeout. Set explicit timeouts for hooks that do I/O or network calls.

8. **Async hooks cannot block**: Hooks with `"async": true` run in the background. They cannot block tool use or emit warnings that the agent sees in real time. Use async only for telemetry, indexing, and other fire-and-forget work.

---

## Validation Scripts

Run the appropriate validator to check your work programmatically:

```bash
# Validate a skill directory
bash ${CLAUDE_SKILL_DIR}/scripts/validate-skill.sh /path/to/skill-directory

# Validate a hook script
bash ${CLAUDE_SKILL_DIR}/scripts/validate-hook.sh /path/to/hook-script.sh

# Validate an agent definition
bash ${CLAUDE_SKILL_DIR}/scripts/validate-agent.sh /path/to/agent.md
```

Each validator checks structure, conventions, safety patterns, and outputs PASS/FAIL/WARN for every check.

---

## Verification Checklist

Run through this before considering any extension complete:

- [ ] All shell scripts start with `set -euo pipefail`
- [ ] Hook scripts consume stdin (`hook_init`) before any other operation
- [ ] External tool calls are guarded with `command -v` or `2>/dev/null || true`
- [ ] No hardcoded paths — use `$SCRIPT_DIR`, `$CLAUDE_PLUGIN_ROOT`, or `get_repo_root`
- [ ] Session identity uses `get_session_id`, not `$PPID`
- [ ] Worktree-aware: uses `get_repo_root` instead of `$(pwd)` for repo root
- [ ] Exit codes follow the contract (0/1/2) for the hook type
- [ ] Tests exist and pass (`bats` for shell, `vitest` for TypeScript)
- [ ] No manual version bumps — commit messages use conventional format
- [ ] All changes are in `plugin/`, not `plugins/`
- [ ] Script syntax is valid: `bash -n script.sh` passes
- [ ] Synchronous hooks complete in under 100ms
