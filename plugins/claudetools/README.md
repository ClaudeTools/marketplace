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
  <a href="https://github.com/ClaudeTools/marketplace"><img alt="Version" src="https://img.shields.io/badge/version-6.0.0-7BCC2E?style=flat-square"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"></a>
  <a href="https://code.claude.com/docs/en/plugins"><img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-plugin-7BCC2E?style=flat-square"></a>
</p>

---

<!-- TODO: Replace with recorded GIF demo -->
<!--
<p align="center">
  <img src="assets/img/demo.gif" alt="claudetools in action" width="720">
</p>
-->

## What is claudetools?

claudetools is a plugin for [Claude Code](https://code.claude.com) that makes AI-assisted development safer and more productive. It installs instantly and works everywhere — no configuration required.

- **51 hooks** across 17 lifecycle events catch destructive commands, enforce code quality, and track session metrics
- **14 skills** for structured workflows — codebase exploration, prompt engineering, bug investigation, UI design, task management
- **10 agents** including 4 pre-built pipelines for feature development, bug fixing, security audits, and refactoring
- **Adaptive thresholds** that learn from your sessions — per-model sensitivity tuning, quiet mode for research

## Install

```
/plugin install claudetools@claudetools-marketplace
```

That's it. Hooks activate immediately. Skills are available via `/skill-name`.

## Hooks

Hooks intercept Claude's tool calls at every lifecycle event and enforce guardrails automatically.

| Category | What it catches | Examples |
|----------|----------------|----------|
| **Safety** | Destructive commands, hardcoded secrets, sensitive file access | `rm -rf /`, API keys in source, `.env` modifications |
| **Quality** | Stubs, placeholder code, type abuse, edit churn | `throw new Error('not implemented')`, excessive `as any` |
| **Process** | Uncommitted work, scope creep, blind edits | Editing files without reading them first, 10+ uncommitted files |
| **Context** | Redundant reads, session metrics, memory injection | Re-reading unchanged files, injecting learned patterns |

### Quiet mode

Set `CLAUDE_HOOKS_QUIET=1` to suppress all non-safety hooks. Useful for research, documentation, and exploration sessions where quality gates add friction.

```bash
CLAUDE_HOOKS_QUIET=1 claude
```

Safety hooks (stop enforcement, dangerous command blocking, sensitive file guards) always run regardless of quiet mode.

## Skills

| Skill | Command | What it does |
|-------|---------|-------------|
| **Explore Codebase** | `/exploring-codebase` | Semantic code navigation via tree-sitter index — find symbols, trace imports, detect dead code, map architecture |
| **Improve Prompts** | `/improving-prompts` | Transform rough instructions into structured XML prompts, then execute or create task trees |
| **Investigate Bugs** | `/investigating-bugs` | Evidence-based debugging: reproduce, observe, hypothesize, verify, fix, confirm |
| **Design Interfaces** | `/designing-interfaces` | Production-grade frontend UI with design system generation, responsive screenshots, contrast auditing |
| **Manage Tasks** | `/managing-tasks` | Persistent task system with cross-session continuity, decomposition, and handoff |
| **Evaluate Safety** | `/evaluating-safety` | Training scenarios, deterministic tests, and cross-model safety evaluation |
| **Improve Plugin** | `/improving-plugin` | Self-improvement loop with before/after measurement |
| **Code Review** | `/code-review` | 4-pass structured review: correctness, security, performance, maintainability |
| **Session Dashboard** | `/session-dashboard` | System health, success rates, failure patterns, token efficiency |
| **Field Review** | `/field-review` | Plugin self-audit: hook block rates, false positives, gaps |

## Agent Pipelines

Pre-built multi-step workflows that compose skills into end-to-end processes.

| Pipeline | Steps | Use when |
|----------|-------|----------|
| **Feature** | explore &rarr; plan &rarr; implement (parallel) &rarr; review &rarr; verify | Building a new feature end-to-end |
| **Bugfix** | explore &rarr; investigate &rarr; fix &rarr; review &rarr; confirm | Structured, evidence-based bug resolution |
| **Security** | full-audit &rarr; security-scan &rarr; dead-code &rarr; dependency-audit &rarr; report | Read-only security assessment |
| **Refactor** | change-impact &rarr; decompose &rarr; implement (parallel) &rarr; verify | Safe refactoring with regression checks |

## Codebase Pilot

claudetools includes **codebase-pilot**, a tree-sitter + SQLite indexing engine that powers semantic code navigation. It supports TypeScript, JavaScript, Python natively, plus 11 WASM languages (Go, Rust, Java, Kotlin, Ruby, C#, PHP, Swift, C, C++, Bash).

```bash
# Project overview
codebase-pilot map

# Find any symbol
codebase-pilot find-symbol "handleAuth"

# Trace what breaks if you change something
codebase-pilot change-impact "handleAuth"

# Find unused exports
codebase-pilot dead-code

# Security scan with structural analysis
codebase-pilot security-scan --all
```

The index updates automatically on file edits via hooks.

## Configuration

### Adaptive thresholds

Thresholds for edit frequency, failure detection, and commit enforcement are stored in an SQLite metrics database. They adjust per-model (opus/sonnet/haiku) based on session outcomes.

### Memory system

claudetools indexes your project memory files into an FTS5-backed database for fast retrieval. Memories are injected into session context based on confidence scores, with automatic decay for stale entries.

A contradiction detector (`memory-validate.sh`) compares CLAUDE.md directives against stored memories and flags conflicts at session start.

### Skill loading

Frequently-used skills (exploring-codebase, investigating-bugs, improving-prompts, designing-interfaces) auto-load when triggered by your message. Specialized skills (evaluating-safety, improving-plugin, managing-tasks) load only on explicit `/skill-name` invocation, keeping context overhead low.

## Project structure

```
claudetools/
  .claude-plugin/plugin.json   Plugin manifest
  hooks/hooks.json              Hook registration (17 lifecycle events)
  scripts/                      Hook scripts and validators
    lib/                        Shared libraries (pilot-query, telemetry, etc.)
    validators/                 Modular validation functions
  skills/                       Skill definitions (SKILL.md + scripts)
  agents/                       Agent pipeline definitions
  codebase-pilot/               Tree-sitter indexing engine
  agent-mesh/                   Multi-agent coordination CLI
  task-system/                  MCP-based task persistence server
```

## Requirements

- [Claude Code](https://code.claude.com) v1.0+
- Node.js 18+ (for codebase-pilot and MCP server)
- SQLite3 (for metrics and indexing)
- jq (recommended, for hook input parsing)

## License

MIT

---

<p align="center">
  <a href="https://claudetools.com">claudetools.com</a>
</p>
