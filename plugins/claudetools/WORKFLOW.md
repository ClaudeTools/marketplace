# Claudetools Workflow

Three commands. That's it.

```
/design → /build → /ship
```

## How it works

### `/design` — Figure out what to build

Tell Claude what you want. It will:

1. **Explore** your codebase to understand what exists
2. **Research** any external APIs or libraries involved
3. **Present 2-3 approaches** with tradeoffs — you pick one
4. **Write an implementation plan** with exact files and steps

You approve the design before any code is written.

### `/build` — Build it with tests

Claude executes the plan:

1. **Writes a failing test** for each task
2. **Implements the minimum code** to make it pass
3. **Commits** after each task
4. **Reports progress** as it goes

You see: "Task 3/7 complete. Tests: 18/18 passing."

### `/ship` — Review, PR, deploy

Claude delivers the work:

1. **Runs a code review** (correctness, security, performance)
2. **Creates a PR** with a structured description
3. **Monitors CI** until checks pass
4. **Deploys** if you ask it to

You choose: create PR, merge directly, or deploy.

---

## Other commands

| Command | When to use |
|---------|------------|
| `/debug` | Something's broken — investigate and fix |
| `/explore` | Understand unfamiliar code |
| `/research` | Look up API docs before implementing |
| `/review` | Standalone code review |
| `/health` | Check plugin performance metrics |

---

## You don't need to memorize this

Claude automatically detects what you're asking for and suggests the right workflow. Say "build me a login system" and it starts with `/design`. Say "fix this bug" and it starts with `/debug`.

The workflow happens naturally. The commands are there if you want to jump to a specific phase.

---

## Examples

**New feature:**
> "Add user authentication with OAuth"

Claude: explores codebase → researches OAuth providers → presents approaches → writes plan → builds with TDD → creates PR

**Bug fix:**
> "The login page crashes when email is empty"

Claude: reproduces the bug → identifies root cause → writes test → fixes → verifies → ships

**Quick question:**
> "Where is the payment handler defined?"

Claude: uses codebase-pilot to find it → shows you the file and line
