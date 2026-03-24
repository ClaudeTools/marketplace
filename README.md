<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/img/logo-banner-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/img/logo-banner.svg">
    <img alt="claudetools" src="assets/img/logo-banner.svg" width="420">
  </picture>
</p>

<p align="center">
  <strong>Zero-config guardrails, skills, and agent pipelines for Claude Code</strong>
</p>

<p align="center">
  <a href="https://github.com/ClaudeTools/marketplace"><img src="https://img.shields.io/badge/version-6.0.0-7BCC2E?style=for-the-badge" alt="Version"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="License"></a>&nbsp;
  <a href="https://code.claude.com/docs/en/plugins"><img src="https://img.shields.io/badge/Claude_Code-plugin-7BCC2E?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0id2hpdGUiPjxwYXRoIGQ9Ik04IDZMNCAxMkw4IDE4IiBzdHJva2U9IndoaXRlIiBzdHJva2Utd2lkdGg9IjIiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIgZmlsbD0ibm9uZSIvPjxsaW5lIHgxPSIxMCIgeTE9IjE4IiB4Mj0iMTYiIHkyPSIxOCIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiLz48L3N2Zz4=" alt="Claude Code"></a>
</p>

<br>

<p align="center">
  <a href="#install">Install</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#skills">Skills</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#hooks">Hooks</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#agents">Agents</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#codebase-pilot">Codebase Pilot</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;
  <a href="#configuration">Configuration</a>
</p>

<br>

<!-- TODO: Add GIF demo here -->
<!-- <p align="center"><img src="assets/img/demo.gif" alt="claudetools in action" width="720"></p> -->

## Install

```
/plugin install claudetools@claudetools-marketplace
```

> Hooks activate immediately. Skills available via `/skill-name`. No configuration needed.

<br>

## Skills

> 14 built-in skills for structured, repeatable workflows

<table>
<tr>
<td width="50%" valign="top">

#### Code & Analysis
| Command | What it does |
|---------|-------------|
| `/exploring-codebase` | Find symbols, trace imports, detect dead code, map architecture |
| `/investigating-bugs` | Evidence-based debug: reproduce &rarr; observe &rarr; hypothesize &rarr; fix |
| `/code-review` | 4-pass review: correctness, security, performance, maintainability |
| `/improving-prompts` | Transform rough instructions into structured prompts &rarr; execute |

</td>
<td width="50%" valign="top">

#### Build & Manage
| Command | What it does |
|---------|-------------|
| `/designing-interfaces` | Production UI with design systems, responsive screenshots, contrast auditing |
| `/managing-tasks` | Persistent tasks with cross-session continuity and handoff |
| `/session-dashboard` | System health, success rates, failure patterns |
| `/field-review` | Plugin self-audit: hook block rates, false positives, gaps |

</td>
</tr>
</table>

<br>

## Hooks

> 51 hooks across 17 lifecycle events &mdash; guardrails that run automatically on every tool call

<table>
<tr>
<td width="25%" align="center">
<br>

**Safety**

Blocks destructive commands, hardcoded secrets, sensitive file access

`rm -rf` &bull; API keys &bull; `.env`

</td>
<td width="25%" align="center">
<br>

**Quality**

Catches stubs, placeholder code, type abuse, edit churn

`not implemented` &bull; `as any` &bull; churn

</td>
<td width="25%" align="center">
<br>

**Process**

Enforces read-before-edit, commit hygiene, scope discipline

blind edits &bull; uncommitted work

</td>
<td width="25%" align="center">
<br>

**Context**

Prevents redundant reads, injects learned patterns, tracks metrics

re-reads &bull; memory &bull; telemetry

</td>
</tr>
</table>

<details>
<summary><strong>Quiet mode</strong> &mdash; suppress non-safety hooks for research sessions</summary>

```bash
CLAUDE_HOOKS_QUIET=1 claude
```

Safety hooks (stop enforcement, dangerous command blocking, sensitive file guards) always run.

</details>

<br>

## Agents

> 10 agents including 4 pre-built pipelines that compose skills into end-to-end workflows

| Pipeline | Flow | Use when |
|----------|------|----------|
| **Feature** | explore &rarr; plan &rarr; implement &rarr; review &rarr; verify | Building a new feature end-to-end |
| **Bugfix** | explore &rarr; investigate &rarr; fix &rarr; review &rarr; confirm | Structured, evidence-based bug resolution |
| **Security** | full-audit &rarr; scan &rarr; dead-code &rarr; deps &rarr; report | Read-only security assessment |
| **Refactor** | impact-analysis &rarr; decompose &rarr; implement &rarr; verify | Safe refactoring with regression checks |

Plus standalone agents: `architect` &bull; `implementing-features` &bull; `code-reviewer` &bull; `test-writer` &bull; `researcher` &bull; `investigating-bugs`

<br>

## Codebase Pilot

> Tree-sitter + SQLite indexing engine &mdash; semantic code navigation across 14 languages

```bash
codebase-pilot map                        # Project overview
codebase-pilot find-symbol "handleAuth"   # Locate any function, class, or type
codebase-pilot change-impact "handleAuth" # What breaks if this changes?
codebase-pilot dead-code                  # Find unused exports
codebase-pilot circular-deps              # Detect circular imports
```

**Languages:** TypeScript, JavaScript, Python (native) + Go, Rust, Java, Kotlin, Ruby, C#, PHP, Swift, C, C++ (WASM)

The index updates automatically on file edits via hooks.

<br>

## Configuration

<details>
<summary><strong>Adaptive thresholds</strong></summary>

Thresholds for edit frequency, failure detection, and commit enforcement are stored in an SQLite metrics database. They adjust per-model (opus/sonnet/haiku) based on session outcomes.

</details>

<details>
<summary><strong>Memory system</strong></summary>

Project memory files are indexed into an FTS5-backed database for fast retrieval. Memories inject into session context based on confidence scores with automatic decay for stale entries.

A contradiction detector compares CLAUDE.md directives against stored memories and flags conflicts at session start.

</details>

<details>
<summary><strong>Skill loading</strong></summary>

Frequently-used skills auto-load when triggered by your message. Specialized skills load only on explicit `/skill-name` invocation, keeping context overhead low.

</details>

<br>

## Project structure

```
claudetools/
  .claude-plugin/plugin.json    Plugin manifest
  hooks/hooks.json               17 lifecycle events
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

- [Claude Code](https://code.claude.com) v1.0+ &bull; Node.js 18+ &bull; SQLite3 &bull; jq (recommended)

## License

MIT

---

<p align="center">
  <a href="https://claudetools.com">claudetools.com</a>
</p>
