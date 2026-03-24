# Recommended CLAUDE.md Snippet for claudetools Users

Add the following to your project's CLAUDE.md or `~/.claude/CLAUDE.md` to help Claude leverage the plugin effectively. This is optional — the plugin's rules and skills load automatically. This snippet provides a quick reference so Claude knows what's available.

---

```markdown
## claudetools Plugin

This project uses the claudetools plugin. Key capabilities:

### Navigation
- Use `/exploring-codebase` or ask to "explore the codebase" — auto-navigates with codebase-pilot CLI
- Run `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map` for project overview

### Workflows
- `/improving-prompts` — structure rough requests into detailed XML prompts
- `/managing-tasks` — persistent task tracking across sessions
- `/investigating-bugs` — evidence-based debugging (reproduce → observe → hypothesize → verify → fix)
- `/designing-interfaces` — UI/UX design with Refactoring UI principles

### Commands
- `/code-review` — structured 4-pass review (correctness, security, performance, maintainability)
- `/memory` — manage cross-session knowledge
- `/logs` — query session history and errors
- `/mesh` — coordinate with other agents in the same repo

### Agents (auto-delegated)
- architect (opus, read-only) — design reviews
- implementing-features (sonnet) — multi-file feature work
- investigating-bugs (sonnet) — debugging
- code-reviewer (sonnet, read-only) — code quality
- researcher (sonnet, read-only) — external API/library research
- test-writer (sonnet) — test generation
```

---

**Note:** Do not add this if your CLAUDE.md is already near 200 lines. The plugin's own rules/ files already load these instructions at session start.
