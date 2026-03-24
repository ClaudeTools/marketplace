<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/img/logo-dark.png">
    <img alt="claudetools" src="assets/img/logo-light.png" width="380">
  </picture>
</p>

<p align="center">
  <strong>Zero-config guardrails, skills, and agent pipelines for Claude Code</strong>
</p>

<p align="center">
  <a href="https://github.com/ClaudeTools/marketplace"><img src="https://img.shields.io/badge/version-6.0.0-1A7F37?style=for-the-badge" alt="Version"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-0550AE?style=for-the-badge" alt="License"></a>&nbsp;
  <img src="https://img.shields.io/badge/hooks-51-1A7F37?style=for-the-badge" alt="51 Hooks">&nbsp;
  <img src="https://img.shields.io/badge/skills-14-1A7F37?style=for-the-badge" alt="14 Skills">&nbsp;
  <img src="https://img.shields.io/badge/agents-10-1A7F37?style=for-the-badge" alt="10 Agents">
</p>

<p align="center">
  <a href="#-install">Install</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#-skills">Skills</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#-hooks">Hooks</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#-agents">Agents</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#-codebase-pilot">Codebase Pilot</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#-configuration">Config</a>
</p>

<br>

## <img src="https://img.shields.io/badge/->_-1A7F37?style=flat-square" alt="" height="20"> Install

```
/plugin install claudetools@claudetools-marketplace
```

> Hooks activate immediately. Skills available via `/skill-name`. No configuration needed.

<br>

## <img src="https://img.shields.io/badge/-Skills-1A7F37?style=flat-square" alt="" height="20"> Skills

14 built-in skills for structured, repeatable workflows. Invoke with `/skill-name`.

<details open>
<summary><img src="https://img.shields.io/badge/-explore-1D4ED8?style=flat-square" alt=""> <strong>Explore Codebase</strong> &mdash; <code>/exploring-codebase</code></summary>

Semantic code navigation powered by codebase-pilot. Find symbol definitions, trace import chains, map project architecture, detect dead code, analyse change impact, and check circular dependencies. Uses tree-sitter AST parsing across 14 languages. Modes: map, find-symbol, file-overview, related-files, navigate, dead-code, change-impact, security-scan, complexity-report, full-audit.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-debug-B91C1C?style=flat-square" alt=""> <strong>Investigate Bugs</strong> &mdash; <code>/investigating-bugs</code></summary>

Evidence-based debugging that enforces a strict protocol: **REPRODUCE** the error, **OBSERVE** the code and logs, **HYPOTHESIZE** with evidence, **VERIFY** the hypothesis before fixing, **FIX** the root cause, **CONFIRM** with tests. Two-strike rule: if the second fix fails, step back and re-gather evidence from scratch.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-review-6D28D9?style=flat-square" alt=""> <strong>Code Review</strong> &mdash; <code>/code-review</code></summary>

Structured 4-pass review covering correctness, security, performance, and maintainability. Each pass uses confidence-based filtering to surface only high-priority findings. Outputs file:line references with severity ratings.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-prompt-92400E?style=flat-square" alt=""> <strong>Improve Prompts</strong> &mdash; <code>/improving-prompts</code></summary>

Transforms rough instructions into structured XML prompts using prompting science (examples with reasoning, escape clauses, verification blocks). Three modes: **execute** (generate and run immediately), **plan** (generate, review, then decide), **task** (generate and create persistent task tree for later execution). Auto-detects tech stack, test commands, and project conventions.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-design-BE185D?style=flat-square" alt=""> <strong>Design Interfaces</strong> &mdash; <code>/designing-interfaces</code></summary>

Production-grade frontend UI with design intent. Generates CSS design systems (colour palettes, type scales, spacing tokens) from a theme seed. Includes responsive screenshot capture at 4 breakpoints, contrast matrix auditing, pixel-diff regression testing, and accessibility checks. Supports React, Next.js, Vite, Astro, SvelteKit, Tailwind CSS, and plain HTML/CSS. Build mode for new projects, maintain mode for existing ones.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-tasks-065F46?style=flat-square" alt=""> <strong>Manage Tasks</strong> &mdash; <code>/managing-tasks</code></summary>

Persistent task system with cross-session continuity. Subcommands: **new** (create with codebase-pilot enrichment), **start** (pick next task and spawn team), **stop** (mark done, record files touched), **status** (markdown report), **restore** (recover tasks from prior session), **decompose** (AI-assisted breakdown into 3-7 subtasks), **progress** (narrative progress tracking), **handoff** (session summary for next developer), **validate** (deterministic task quality checks).
</details>

<details>
<summary><img src="https://img.shields.io/badge/-safety-991B1B?style=flat-square" alt=""> <strong>Evaluate Safety</strong> &mdash; <code>/evaluating-safety</code></summary>

Run training scenarios, deterministic tests, and safety corpus evaluations. Single-domain commands: test, code, noncode, edge, headless, golden, compare. Parallel commands (uses TeamCreate): all, compare-models, cross-model, golden-cross-model. Produces pass/fail reports per scenario with deviation tracking.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-improve-155E75?style=flat-square" alt=""> <strong>Improve Plugin</strong> &mdash; <code>/improving-plugin</code></summary>

Autonomous 7-phase self-improvement loop: collect data, verify prior changes, analyse findings, prioritise by impact, capture baseline metrics, implement fixes, measure after-state. Categorises findings (hook-coverage, noise-reduction, safety-corpus, etc.) and logs outcomes with before/after measurement. Reverts regressions automatically.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-health-1A7F37?style=flat-square" alt=""> <strong>Session Dashboard</strong> &mdash; <code>/session-dashboard</code></summary>

Human-readable report of system health: hook fire counts and block rates, tool success/failure rates, edit churn metrics, memory injection stats, and token efficiency. Useful for diagnosing noisy hooks or identifying workflow friction.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-audit-4338CA?style=flat-square" alt=""> <strong>Field Review</strong> &mdash; <code>/field-review</code></summary>

Plugin self-audit that grades hook performance from real session data. Reports block rates (target <10% for non-safety hooks), false positive patterns, dead hooks (0-fire entries), skill usage rates, and context token overhead. Produces an overall letter grade per component.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-memory-5B21B6?style=flat-square" alt=""> <strong>Memory</strong> &mdash; <code>/memory</code></summary>

Manage persistent cross-session knowledge. Search, create, update, and delete memory entries. FTS5-backed full-text search with confidence scoring and automatic decay for stale entries.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-logs-4B5563?style=flat-square" alt=""> <strong>Logs</strong> &mdash; <code>/logs</code></summary>

Extract and query Claude Code session logs. Search conversation history, tool usage patterns, errors, and side-questions across sessions.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-docs-0369A1?style=flat-square" alt=""> <strong>Docs Manager</strong> &mdash; <code>/docs-manager</code></summary>

Manage project documentation with standardised structure. Audit existing docs for staleness, generate index files, archive outdated content, and maintain consistent formatting.
</details>

<details>
<summary><img src="https://img.shields.io/badge/-guide-9A3412?style=flat-square" alt=""> <strong>Claude Code Guide</strong> &mdash; <code>/claude-code-guide</code></summary>

Best practices reference for building Claude Code extensions. Covers skills, hooks, agents, plugins, slash commands, scripts, MCP servers, CLAUDE.md, memory, and task systems.
</details>

<br>

## <img src="https://img.shields.io/badge/-Hooks-1D4ED8?style=flat-square" alt="" height="20"> Hooks

51 hooks across 17 lifecycle events. Guardrails that run automatically on every tool call.

<table>
<tr>
<td width="25%" align="center">

<img src="https://img.shields.io/badge/-SAFETY-B91C1C?style=for-the-badge" alt="Safety">

Destructive commands
Hardcoded secrets
Sensitive file access

</td>
<td width="25%" align="center">

<img src="https://img.shields.io/badge/-QUALITY-6D28D9?style=for-the-badge" alt="Quality">

Stubs & placeholders
Type abuse (`as any`)
Edit churn detection

</td>
<td width="25%" align="center">

<img src="https://img.shields.io/badge/-PROCESS-92400E?style=for-the-badge" alt="Process">

Read-before-edit
Commit hygiene
Scope discipline

</td>
<td width="25%" align="center">

<img src="https://img.shields.io/badge/-CONTEXT-065F46?style=for-the-badge" alt="Context">

Redundant read prevention
Memory injection
Session telemetry

</td>
</tr>
</table>

<details>
<summary><img src="https://img.shields.io/badge/-quiet_mode-4B5563?style=flat-square" alt=""> Suppress non-safety hooks for research sessions</summary>

<br>

```bash
CLAUDE_HOOKS_QUIET=1 claude
```

Safety hooks always run regardless of quiet mode.

</details>

<br>

## <img src="https://img.shields.io/badge/-Agents-BE185D?style=flat-square" alt="" height="20"> Agents

10 agents including 4 pre-built pipelines that compose skills into end-to-end workflows.

| Pipeline | Flow | Use when |
|----------|------|----------|
| <img src="https://img.shields.io/badge/-feature-1A7F37?style=flat-square" alt=""> | explore &rarr; plan &rarr; implement &rarr; review &rarr; verify | New feature end-to-end |
| <img src="https://img.shields.io/badge/-bugfix-B91C1C?style=flat-square" alt=""> | explore &rarr; investigate &rarr; fix &rarr; review &rarr; confirm | Evidence-based bug resolution |
| <img src="https://img.shields.io/badge/-security-991B1B?style=flat-square" alt=""> | audit &rarr; scan &rarr; dead-code &rarr; deps &rarr; report | Read-only security assessment |
| <img src="https://img.shields.io/badge/-refactor-4338CA?style=flat-square" alt=""> | impact &rarr; decompose &rarr; implement &rarr; verify | Safe refactoring |

<details>
<summary>Standalone agents</summary>

`architect` &bull; `implementing-features` &bull; `code-reviewer` &bull; `test-writer` &bull; `researcher` &bull; `investigating-bugs`

</details>

<br>

## <img src="https://img.shields.io/badge/-Codebase_Pilot-155E75?style=flat-square" alt="" height="20"> Codebase Pilot

Tree-sitter + SQLite indexing engine. Semantic code navigation across 14 languages.

```bash
codebase-pilot map                        # Project overview
codebase-pilot find-symbol "handleAuth"   # Locate any function, class, or type
codebase-pilot change-impact "handleAuth" # What breaks if this changes?
codebase-pilot dead-code                  # Find unused exports
codebase-pilot circular-deps              # Detect circular imports
```

<p>
  <img src="https://img.shields.io/badge/TypeScript-1D4ED8?style=flat-square&logo=typescript&logoColor=white" alt="TypeScript">
  <img src="https://img.shields.io/badge/JavaScript-92400E?style=flat-square&logo=javascript&logoColor=white" alt="JavaScript">
  <img src="https://img.shields.io/badge/Python-1E3A5F?style=flat-square&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Go-155E75?style=flat-square&logo=go&logoColor=white" alt="Go">
  <img src="https://img.shields.io/badge/Rust-1C1917?style=flat-square&logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/Java-9A3412?style=flat-square&logo=openjdk&logoColor=white" alt="Java">
  <img src="https://img.shields.io/badge/Kotlin-5B21B6?style=flat-square&logo=kotlin&logoColor=white" alt="Kotlin">
  <img src="https://img.shields.io/badge/Ruby-991B1B?style=flat-square&logo=ruby&logoColor=white" alt="Ruby">
  <img src="https://img.shields.io/badge/C%23-065F46?style=flat-square&logo=csharp&logoColor=white" alt="C#">
  <img src="https://img.shields.io/badge/PHP-4338CA?style=flat-square&logo=php&logoColor=white" alt="PHP">
  <img src="https://img.shields.io/badge/Swift-9A3412?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/C/C++-1D4ED8?style=flat-square&logo=cplusplus&logoColor=white" alt="C/C++">
  <img src="https://img.shields.io/badge/Bash-1A7F37?style=flat-square&logo=gnubash&logoColor=white" alt="Bash">
</p>

Index updates automatically on file edits via hooks.

<br>

## <img src="https://img.shields.io/badge/-Config-92400E?style=flat-square" alt="" height="20"> Configuration

<details>
<summary><strong>Memory system</strong> &mdash; FTS5-backed cross-session knowledge</summary>

<br>

Project memory files indexed for fast retrieval. Confidence-scored injection with automatic decay. Contradiction detector flags conflicts between CLAUDE.md and stored memories.

</details>

<details>
<summary><strong>Quiet mode</strong> &mdash; silence non-safety hooks</summary>

<br>

`CLAUDE_HOOKS_QUIET=1` suppresses all quality/process/context hooks. Safety hooks always run.

</details>

<br>

## Project structure

```
claudetools/
  hooks/hooks.json               17 lifecycle events, 51 hooks
  scripts/                       44 hook scripts
    lib/                         9 shared libraries
    validators/                  26 modular validators
  skills/                        14 skill definitions
  agents/                        10 agent pipelines
  codebase-pilot/                Tree-sitter indexing engine
  agent-mesh/                    Multi-agent coordination
  task-system/                   MCP task persistence server
```

## Requirements

[Claude Code](https://code.claude.com) v1.0+ &bull; Node.js 18+ &bull; SQLite3 &bull; jq (recommended)

## License

MIT

---

<p align="center">
  <a href="https://claudetools.com">claudetools.com</a>
</p>
