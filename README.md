<p align="center">
  <h1 align="center">claudetools</h1>
  <p align="center">
    <strong>Make Claude Code reliable.</strong>
    <br />
    <em>Deterministic guardrails, self-learning quality gates, and structured workflows.</em>
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-7C3AED?style=flat-square" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/version-3.1.0-blue?style=flat-square" alt="v3.1.0">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-22c55e?style=flat-square" alt="MIT License"></a>
</p>

---

### The problem

You ask Claude to build something. It says "done." You check -- the function is empty, the tests were not run, and the "fix" was a guess.

### The fix

```
/plugin marketplace add owenob1/claude-code
/plugin install claudetools@owenob1-skills
```

Zero config. Works immediately. Adapts over time.

---

## What you get

### Guardrails (install and forget)

Every Claude Code session automatically gets:

- **40+ checks** on every tool call -- stubs blocked, tests enforced, git workflow protected
- **Codebase auto-indexed** -- tree-sitter maps your project so agents know where things are
- **Permission acceleration** -- safe commands (tests, linting, reads) auto-approved, no dialog fatigue
- **Context preservation** -- critical state survives conversation compaction
- **Self-learning** -- guardrails tune themselves based on your session patterns

### Skills (structured workflows)

| Skill | Invoke | What it does |
|:---|:---|:---|
| **prompt-improver** | `/prompt-improver <task>` | Transforms rough ideas into structured XML prompts, then executes |
| **code-review** | `/code-review` | 4-pass review: correctness, security, performance, maintainability |
| **debug-investigator** | `/debug-investigator <error>` | Evidence-based debugging: REPRODUCE, OBSERVE, HYPOTHESIZE, VERIFY, FIX, CONFIRM |
| **tune-thresholds** | `/tune-thresholds` | Analyse session metrics, recommend guardrail threshold adjustments |
| **session-dashboard** | `/session-dashboard` | Health report: failure trends, edit churn, token efficiency |

### Agents (specialised subagents)

| Agent | Model | Access | Purpose |
|:---|:---|:---|:---|
| **code-reviewer** | Sonnet | Read-only | Structured code quality review |
| **test-writer** | Sonnet | Full | Generate and run tests following project patterns |
| **researcher** | Sonnet | Read-only | Research external APIs and docs before implementation |
| **architect** | Opus | Read-only | Architecture analysis and planning |

---

## What it catches

**Code quality**

| Claude tries to... | Result |
|:---|:---|
| Write a TODO or empty function | Blocked |
| Say "done" without running tests | Blocked |
| Fix a bug without reading the error | Flagged |
| Guess at an API without checking docs | Flagged |
| Edit the same file 3+ times (guessing) | Warned, suggest rewrite |
| Write mocks in production code | Warned |
| Fail the same tool 3 times | Blocked, forced rethink |

**Git and safety**

| Claude tries to... | Result |
|:---|:---|
| Work directly on main/master | Blocked |
| Force push, git reset --hard | Blocked |
| git add -A or git add . | Blocked |
| Finish task with uncommitted changes | Blocked |
| Read .env (debugging) | Allowed |
| Edit .env, credentials, keys | Blocked |
| rm -rf on broad paths | Blocked |
| Deploy without verifying | Flagged |

---

## How it works

Most guardrails are prompts -- the model can ignore them. claudetools uses shell scripts that run outside the model. It cannot talk its way past `exit 2`.

| Layer | Count | Speed | Purpose |
|:---|:---|:---|:---|
| Shell scripts | 35+ | Instant | Mechanical checks: stubs, commits, files, patterns |
| AI checks (Haiku) | 4 | ~2 seconds | Judgment calls: scope, completeness, research |
| Self-learning | 3 | Background | Telemetry, aggregation, threshold tuning |

### Lifecycle coverage

17 of 21 Claude Code hook events covered:

```
SessionStart ---- index codebase, inject learned patterns
UserPromptSubmit - inject git state, active task, recent failures
PreToolUse ------ block dangerous commands, stubs, sensitive files
PermissionRequest auto-approve safe read/test/lint commands
PostToolUse ----- verify output, track edits, record telemetry
PostToolUseFailure track failures, block after 3 same-tool fails
TaskCompleted --- quality gate, verify requirements, check commits
TeammateIdle ---- quality + commit checks
SubagentStop ---- independent verification of subagent work
Stop ------------ multi-tier session review
PreCompact ------ archive critical state before compaction
PostCompact ----- restore context after compaction
Notification ---- desktop alerts for permission/idle prompts
ConfigChange ---- audit trail for config modifications
InstructionsLoaded inject project-type-specific rules
SessionEnd ------ aggregate metrics, cleanup
SubagentStart --- index codebase for subagent
```

### Self-learning

Sessions generate telemetry. Metrics aggregate at session end. Next session starts with learned patterns.

```
Tool calls --> metrics.db --> session aggregation --> threshold tuning
                                                          |
                                    Next session gets: "high edit churn detected,
                                    focus on diagnostics before editing"
```

Thresholds drift within safety bounds [0.5x, 2.0x] of defaults. Immutable rules (blocked commands, sensitive files) can never be tuned.

---

## Requirements

- [Claude Code](https://code.claude.com) CLI
- [jq](https://jqlang.github.io/jq/download/) -- `brew install jq` (Mac) or `apt install jq` (Linux)
- Node.js (for codebase-pilot MCP server)
- sqlite3 (for metrics -- `brew install sqlite3` or usually pre-installed)

---

<details>
<summary>Full hook reference</summary>

**PreToolUse (10):** block dangerous bash, AI safety check, block restructuring, guard sensitive files, block stubs, require active task, enforce research, enforce deterministic tools, use codebase index, enforce teams

**PostToolUse (7):** verify no stubs, edit frequency guard, mock detection, deploy verification, agent output audit, semantic audit, capture telemetry

**TaskCompleted (5):** quality gate, task verification, commit check, test evidence, process review

**Session lifecycle (12):** index on start, inject context on prompt, auto-approve safe permissions, context archive/restore on compaction, desktop notifications, config audit, dynamic rules, independent subagent verification, idle checks, stop gate, session metrics, session wrap-up

</summary>
</details>

---

<p align="center">
  <a href="LICENSE.txt">MIT License</a> &middot; Built by <a href="https://github.com/owenob1">Owen Innes</a>
</p>
