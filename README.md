<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/img/logo-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/img/logo-light.png">
    <img alt="claudetools" src="assets/img/logo-light.png" width="380">
  </picture>
</div>

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

14 built-in skills for structured, repeatable workflows.

| | Skill | Command |
|---|-------|---------|
| <img src="https://img.shields.io/badge/-explore-1D4ED8?style=flat-square" alt=""> | **Explore Codebase** | `/exploring-codebase` |
| <img src="https://img.shields.io/badge/-debug-B91C1C?style=flat-square" alt=""> | **Investigate Bugs** | `/investigating-bugs` |
| <img src="https://img.shields.io/badge/-review-6D28D9?style=flat-square" alt=""> | **Code Review** | `/code-review` |
| <img src="https://img.shields.io/badge/-prompt-92400E?style=flat-square" alt=""> | **Improve Prompts** | `/improving-prompts` |
| <img src="https://img.shields.io/badge/-design-BE185D?style=flat-square" alt=""> | **Design Interfaces** | `/designing-interfaces` |
| <img src="https://img.shields.io/badge/-tasks-065F46?style=flat-square" alt=""> | **Manage Tasks** | `/managing-tasks` |
| <img src="https://img.shields.io/badge/-safety-991B1B?style=flat-square" alt=""> | **Evaluate Safety** | `/evaluating-safety` |
| <img src="https://img.shields.io/badge/-improve-155E75?style=flat-square" alt=""> | **Improve Plugin** | `/improving-plugin` |
| <img src="https://img.shields.io/badge/-health-1A7F37?style=flat-square" alt=""> | **Session Dashboard** | `/session-dashboard` |
| <img src="https://img.shields.io/badge/-audit-4338CA?style=flat-square" alt=""> | **Field Review** | `/field-review` |

<details>
<summary>+ 4 more: <code>/memory</code> &bull; <code>/logs</code> &bull; <code>/docs-manager</code> &bull; <code>/claude-code-guide</code></summary>

| | Skill | Command |
|---|-------|---------|
| <img src="https://img.shields.io/badge/-memory-5B21B6?style=flat-square" alt=""> | **Memory** | `/memory` |
| <img src="https://img.shields.io/badge/-logs-4B5563?style=flat-square" alt=""> | **Logs** | `/logs` |
| <img src="https://img.shields.io/badge/-docs-0369A1?style=flat-square" alt=""> | **Docs Manager** | `/docs-manager` |
| <img src="https://img.shields.io/badge/-guide-9A3412?style=flat-square" alt=""> | **Claude Code Guide** | `/claude-code-guide` |

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
