---
title: Improve Prompts
parent: Guides
nav_order: 8
---

# Improve Prompts

Use `/prompt-improver` to transform a rough request into a structured XML prompt and execute it — or review it, or convert it into a tracked task — in three modes.
{: .fs-6 .fw-300 }

## What you need
- claudetools installed
- A rough description of what you want Claude to do

## Steps

### 1. Choose a mode

| Mode | Command | What it does |
|------|---------|-------------|
| Execute (default) | `/prompt-improver <request>` | Generates a structured prompt and runs it immediately |
| Plan | `/prompt-improver plan <request>` | Generates the prompt and shows it for review before running |
| Task | `/prompt-improver task <request>` | Generates the prompt and creates persistent tasks — does not execute |

### 2. Execute mode — just run it

For a rough request you trust, use execute mode:

```
/prompt-improver add pagination to the invoices API endpoint
```

Claude:
1. Detects the tech stack and gathers codebase context
2. Spawns a generation agent to produce a structured XML prompt
3. Shows you a 2–3 sentence plan of what it is about to do
4. Executes the prompt immediately — implementing the change, verifying it, and committing

Use this when the request is clear enough that you are comfortable with Claude proceeding without showing you the full plan.

### 3. Plan mode — review before running

For anything non-trivial, use plan mode to see the generated prompt first:

```
/prompt-improver plan refactor the auth module to use JWT instead of sessions
```

Claude generates the prompt and presents it in a code fence with a summary of:
- What codebase context was gathered
- What assumptions were made
- How many tasks are involved
- Whether parallel execution is recommended

You then choose:

```
Execute — run this prompt as-is
Revise  — tell me what to change
Edit    — paste back a modified prompt
Discard — cancel
```

Use this for large or risky changes where you want to verify the plan before implementation starts.

### 4. Task mode — convert to tracked tasks

For a feature or piece of work you want to schedule rather than run now:

```
/prompt-improver task build a CSV export feature for the invoices page
```

Claude:
1. Generates the same structured XML prompt as execute/plan modes
2. Creates a parent task in the task system
3. Creates subtasks for each phase, with acceptance criteria and verification commands
4. Shows you the task tree with IDs

Then starts the work automatically:

```
Created task tree:
- [task-a3f8b2c1] CSV export for invoices (high, prompt-improved)
  - [task-b1c2d3e4] Add /api/invoices/export endpoint (high)
  - [task-e5f6a7b8] Add Export button to invoices UI (medium, depends on: b1c2d3e4)
  - [task-c9d0e1f2] Add integration tests (medium, depends on: b1c2d3e4)
```

## What happens behind the scenes

- A **generation agent** is spawned in a sub-context to build the prompt — this keeps the main conversation clean and prevents context bloat
- The agent reads 4 reference files before generating: an XML template, prompting principles, chaining patterns, and before/after examples
- The generated prompt is validated with `validate-prompt.sh` before being used — structural failures are fixed automatically
- In execute mode, the prompt is followed directly by the main conversation agent — not a subagent
- In task mode, `task_create` is called for each task block in the generated XML, with full metadata (acceptance criteria, file references, verification commands)

## Tips

- Use **execute mode** for focused, single-concern requests (add a field, fix a bug, change a behaviour)
- Use **plan mode** for anything that touches multiple files or involves an architectural decision
- Use **task mode** when you have a backlog item that should be worked on later or by a separate agent
- If the generated prompt looks wrong, use **Revise** to give feedback — the generation agent re-runs with your notes
- The generation agent uses codebase-pilot to find real file paths — the output should never contain invented paths

## Related

- [Manage Tasks](manage-tasks.md) — task mode connects prompt-improver to the task system
- [Build a Feature](build-a-feature.md) — feature-pipeline uses improving-prompts internally for the plan step
- [Reference: improving-prompts skill](../reference/skills.md)
