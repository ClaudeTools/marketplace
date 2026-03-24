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

## <img src="https://img.shields.io/badge/-Commands-4338CA?style=flat-square" alt="" height="20"> Slash Commands

7 utility commands. Invoke explicitly via `/command-name`.

| Command | Description |
|---------|-------------|
| $\color{#8B5CF6}{\textsf{/code-review}}$ | 4-pass structured review: correctness, security, performance, maintainability. Confidence-filtered findings with file:line references. |
| $\color{#22C55E}{\textsf{/session-dashboard}}$ | System health report: hook fire/block rates, tool success/failure, edit churn, token efficiency. |
| $\color{#6366F1}{\textsf{/field-review}}$ | Plugin self-audit from real session data. Block rates, false positives, dead hooks, skill usage, context overhead. |
| $\color{#A78BFA}{\textsf{/memory}}$ | Manage persistent cross-session knowledge. FTS5-backed search, confidence scoring, automatic decay. |
| $\color{#9CA3AF}{\textsf{/logs}}$ | Query session logs: conversation history, tool usage, errors, side-questions across sessions. |
| $\color{#38BDF8}{\textsf{/docs-manager}}$ | Documentation audit: staleness detection, index generation, archiving, consistent formatting. |
| $\color{#FB923C}{\textsf{/claude-code-guide}}$ | Best practices reference for building Claude Code extensions: skills, hooks, agents, plugins, MCP servers. |

<br>

## <img src="https://img.shields.io/badge/-Skills-1A7F37?style=flat-square" alt="" height="20"> Skills

7 intelligent workflows. Claude invokes these automatically when your task matches, or use `/skill-name`.

| Skill | Description |
|-------|-------------|
| $\color{#3B82F6}{\textsf{/exploring-codebase}}$ | Semantic code navigation via tree-sitter index. Find symbols, trace imports, detect dead code, map architecture, analyse change impact. 14 languages. |
| $\color{#EF4444}{\textsf{/investigating-bugs}}$ | Evidence-based debugging: **reproduce** &rarr; **observe** &rarr; **hypothesize** &rarr; **verify** &rarr; **fix** &rarr; **confirm**. Two-strike rule. |
| $\color{#F59E0B}{\textsf{/improving-prompts}}$ | Transform rough instructions into structured XML prompts. Modes: **execute**, **plan**, **task**. Auto-detects tech stack. |
| $\color{#EC4899}{\textsf{/designing-interfaces}}$ | Production UI with generated design systems, responsive screenshots, contrast auditing. React, Next.js, Vite, Astro, SvelteKit, Tailwind. |
| $\color{#10B981}{\textsf{/managing-tasks}}$ | Persistent tasks with cross-session continuity. Subcommands: new, start, stop, status, restore, decompose, progress, handoff, validate. |
| $\color{#EF4444}{\textsf{/evaluating-safety}}$ | Training scenarios, deterministic tests, safety corpus evaluation. Cross-model comparison with deviation tracking. |
| $\color{#06B6D4}{\textsf{/improving-plugin}}$ | Autonomous 7-phase self-improvement: collect, verify, analyse, prioritise, baseline, implement, measure. Auto-reverts regressions. |

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
