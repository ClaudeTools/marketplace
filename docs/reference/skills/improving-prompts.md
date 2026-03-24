---
title: Improving Prompts
parent: Skills
grand_parent: Reference
nav_order: 3
---

# Improving Prompts

Transforms rough user input into structured XML prompts and executes them. Handles triage, codebase context gathering, generation via subagent, validation, and execution.

**Trigger:** Use when the user says "improve prompt", "make this work better", "prompt engineer", or "structure a prompt".

**Invocation:** `/improving-prompts [plan|task] [prompt-text or description]`

---

## Modes

| Invocation | Mode | Behaviour |
|------------|------|-----------|
| `/improving-prompts <prompt>` | **Execute** (default) | Generate, brief summary, execute immediately |
| `/improving-prompts plan <prompt>` | **Plan** | Generate, show full XML, wait for user decision |
| `/improving-prompts task <prompt>` | **Task** | Generate, create persistent tasks via task_create, do not execute |

The first word of arguments is checked for `plan` or `task` (case-insensitive) to select mode.

---

## Workflow Steps

### Phase 1: Generate

1. **Triage the input** — classify as trivial, already execution-ready, rough, or mixed. Skip generation agent for execution-ready input.
2. **Summarise conversation context** — 3-5 sentences of what the user has been working on.
3. **Load reference materials** — XML template, prompting principles, prompt chaining guide, before/after examples.
4. **Spawn generation agent** — passes all reference materials inline; agent gathers codebase context via codebase-pilot CLI, classifies input, builds improved prompt with testable verification, and validates output.

### Phase 2: Execute or Review

**Execute mode:** Brief plan → branch → deterministic operations first → execute (TeamCreate for 3+ independent tasks) → verify per task → commit → final check.

**Plan mode:** Show prompt in XML fence → summarise assumptions → offer Execute / Revise / Edit / Discard options.

**Task mode:** Create parent task via MCP → create subtasks with acceptance criteria, file references, verification commands → present task tree → invoke `/managing-tasks start`.

---

## Example Invocations

```
/improving-prompts Add dark mode to the dashboard
/improving-prompts plan Refactor the payment module to use the new Stripe SDK
/improving-prompts task Build a CSV export feature for the reports page
/improving-prompts path/to/spec.md
```

---

## Related Components

- **managing-tasks skill** — task mode creates tasks executed by this skill
- **designing-interfaces skill** — commonly invoked when improved prompt involves UI work
- **no-shortcuts rule** — governs verification requirements the generated prompt must include
