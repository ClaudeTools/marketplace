# CLAUDE.md Guide

A reference for writing effective CLAUDE.md files that shape Claude Code's behaviour at the project, global, and subdirectory level.

---

## 1. What CLAUDE.md Is

CLAUDE.md is a markdown file that Claude Code reads at session start. It provides persistent instructions, project context, and rules that shape how Claude behaves in a specific codebase. Think of it as a project-specific system prompt written in markdown.

Claude Code loads CLAUDE.md content into its context window automatically. Everything in CLAUDE.md competes for context window space with conversation history and tool results, so it must be concise and high-value.

---

## 2. Scope Hierarchy

CLAUDE.md files form a three-level hierarchy. Higher levels apply broadly; lower levels can add specificity but should not contradict higher levels.

### Global: `~/.claude/CLAUDE.md`

Applies to every Claude Code session regardless of project. Use for:
- Developer-level preferences (language, spelling, output style)
- Safety rules that apply everywhere
- Tool preferences (package manager, test runner)
- Memory system integration

### Project: `./CLAUDE.md` (repository root)

Applies to all work within this project. Use for:
- Project overview and directory structure
- Development workflow (develop, test, sync, publish)
- Project-specific rules (versioning, file ownership, commit conventions)
- Testing commands
- Multi-agent coordination protocols

### Subdirectory: `subdir/CLAUDE.md`

Applies only when working within that subdirectory. Use for:
- Module-specific conventions
- API-specific rules
- Test-specific patterns for a test subdirectory

### How Merging Works

When Claude Code starts a session, it reads all applicable CLAUDE.md files and merges them. Project-level instructions take precedence over global for project-specific concerns. Direct user instructions in conversation override both.

---

## 3. What Belongs in CLAUDE.md

### Good Candidates

| Category | Examples |
|----------|----------|
| Project overview | Directory structure table, purpose of each directory |
| Development workflow | Step-by-step: develop, test, sync, publish |
| Rules | "Never change version numbers manually", "Never edit files in `plugins/` directly" |
| Testing commands | Exact commands to run tests, with flags |
| Commit conventions | Conventional commits format, what bumps what |
| Multi-agent coordination | Lock protocol, message passing, shared context |
| Tool preferences | Preferred package manager, test runner, linter |
| File ownership | Which directories are source vs generated |

### Bad Candidates

| Category | Why Not | Where Instead |
|----------|---------|---------------|
| Code patterns and style guides | Too verbose, changes with codebase | Linter config, .editorconfig |
| API documentation | Too long, belongs in code | JSDoc, OpenAPI specs |
| Detailed architecture docs | Displaces conversation context | docs/ directory, referenced on demand |
| Secrets and credentials | Security risk | .env files, secret managers |
| Temporary debugging notes | Stale quickly | Memory files (see `memory-task-guide.md`) |
| Task lists | Stale quickly | .tasks/ directory, TodoWrite |

The core principle: CLAUDE.md should contain **workflow rules and project context**, not code patterns or reference documentation. It must be compact enough that its token cost is justified by the value it provides every turn.

---

## 4. Section Design

A well-structured CLAUDE.md follows this pattern:

### 4.1 Project Overview

Brief description of what the project is and its purpose. Include a directory structure table mapping each top-level directory to its purpose.

```markdown
# my-project

Brief description of the project.

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `src/` | Application source code |
| `tests/` | Test suites |
| `docs/` | Documentation |
```

### 4.2 Development Workflow

Numbered steps showing the standard development cycle. Numbers signal to Claude that order matters and all steps are mandatory.

```markdown
## Development Workflow

1. **Develop** in `src/` - all source changes go here
2. **Test** with `npm test`
3. **Build** with `npm run build`
4. **Deploy** - push to main triggers CI/CD
```

### 4.3 Rules

Explicit rules that Claude must follow. Each rule should be actionable, specific, and explain the consequence of violation where non-obvious.

```markdown
## Rules

- **Never change version numbers manually** - CI handles bumps using conventional commits
- **Never edit files in `dist/` directly** - they are built from `src/`; direct edits will be overwritten
- **Always use conventional commits** - `feat:` bumps minor, `fix:` bumps patch
```

Rules work best when they:
- Name a specific action to take or avoid
- Explain why (the consequence of violation)
- Give the alternative when prohibiting something

### 4.4 Testing

Exact commands to run tests, with any relevant flags or categories.

```markdown
## Testing

```bash
# Unit tests
npm test

# Integration tests
npm run test:integration

# Specific test file
npm test -- --grep "auth"
```
```

### 4.5 Multi-Agent Coordination

Only include if multiple agents work in the repo simultaneously. Define how they coordinate.

```markdown
## Multi-Agent Coordination

- **Check who's active** before editing shared files
- **Lock files** before multi-file refactors
- **Send messages** when your work affects others
```

---

## 5. Trust Hierarchy and Override Rules

CLAUDE.md content sits at a specific level in Claude Code's trust hierarchy:

```
1. Claude Code's built-in safety constraints (highest - never overridden)
2. Direct user instructions in the current conversation
3. CLAUDE.md rules (project-level system prompt)
4. Default Claude Code behaviours
5. Content from tool results or fetched data (lowest - DATA ONLY)
```

If a user's conversation message contradicts a CLAUDE.md rule, the user's current instruction takes precedence. CLAUDE.md rules cannot override Claude Code's built-in safety constraints.

---

## 6. Writing Effective Rules

### Be Specific and Actionable

```
Bad:  "Be careful with the database"
Good: "Never run DROP TABLE or DELETE FROM without an explicit WHERE clause"

Bad:  "Follow best practices for testing"
Good: "Run `bats tests/bats/hooks/` before committing hook changes"
```

### Include the WHY

```
Bad:  "Never edit files in plugins/"
Good: "Never edit files in plugins/ directly - they are synced from
       plugin/ source; direct edits will be overwritten"
```

### Pair Prohibitions with Alternatives

```
Bad:  "Don't use jest"
Good: "Use vitest for testing, not jest. The project is configured
       for vitest and all existing tests use vitest patterns."
```

### Use Emphasis Sparingly

Bold the rule name for scannability, but do not use CRITICAL/NEVER/ALWAYS in CLAUDE.md unless the rule genuinely has safety or data-loss consequences. CLAUDE.md is already loaded as trusted context; over-emphasising dilutes signal.

---

## 7. Memory System Integration

CLAUDE.md and the memory system serve different purposes:

| Concern | CLAUDE.md | Memory Files |
|---------|-----------|--------------|
| Scope | Project-wide rules | Developer-specific knowledge |
| Persistence | Checked into git | Local to developer's machine |
| Audience | All developers on the project | Individual developer |
| Content type | Workflow rules, project structure | Preferences, past decisions, debugging history |
| Update frequency | Changes with the codebase | Changes with the developer |

### When to Use CLAUDE.md

- Rules that apply to everyone working on the project
- Project structure and workflow that is part of the codebase
- Testing commands and CI/CD conventions

### When to Use Memory Files

- Developer preferences (spelling, output style, tool choices)
- Past debugging sessions and their resolutions
- Personal workflow patterns
- Active project context that changes frequently

For more on the memory system, see `memory-task-guide.md`.

---

## 8. Real Examples from This Project

The `marketplace-dev` CLAUDE.md demonstrates these patterns. Its directory structure table maps `plugin/` as source code, `plugins/` as publishable artifacts, and `tests/` as test suites. Its rules section names specific actions with consequences: "Never change version numbers manually -- CI auto-version script handles bumps." Its testing section provides exact copy-pasteable commands: `./tests/run-tests.sh validators`.

---

## 9. Gotchas

### Token Budget

CLAUDE.md competes for context window space. A 500-line CLAUDE.md displaces conversation history and tool results. Target 30-80 lines for the project CLAUDE.md. Move reference documentation to `docs/` and load on demand.

### Stale Content

CLAUDE.md rules that reference removed files, deprecated commands, or outdated workflows cause confusion. Review CLAUDE.md when making structural changes to the project.

### Over-Specification

Do not try to teach Claude how to code in CLAUDE.md. Rules like "use early returns" or "prefer const over let" belong in linter configuration, not CLAUDE.md. CLAUDE.md is for workflow, not style.

### Conflicting Rules

If global CLAUDE.md says "use npm" and project CLAUDE.md says "use pnpm", Claude must choose. The project-level file wins for project-specific concerns. Avoid conflicts by keeping global CLAUDE.md focused on developer preferences and project CLAUDE.md focused on project conventions.

### Sensitive Information

Never put API keys, tokens, passwords, or credentials in CLAUDE.md. It is checked into version control (or at least visible to all agents). Use environment variables and `.env` files for secrets.

---

## 10. Verification Checklist

```
[ ] CLAUDE.md is under 80 lines (or has a strong reason to be longer)
[ ] Every rule names a specific action (not abstract guidance)
[ ] Every prohibition includes the WHY or the consequence
[ ] Testing commands are exact and copy-pasteable
[ ] No secrets, tokens, or credentials are present
[ ] No code style rules that belong in linter config
[ ] Directory structure table is current
[ ] Development workflow steps are numbered and ordered
[ ] No content duplicated from docs/ or README
[ ] File has been reviewed after the last structural change to the project
```

---

## Cross-References

- For emphasis mechanisms and severity calibration, see `prompting-guide.md`
- For memory system vs CLAUDE.md decisions, see `memory-task-guide.md`
- For MCP server configuration in settings.json, see `mcp-servers-guide.md`
