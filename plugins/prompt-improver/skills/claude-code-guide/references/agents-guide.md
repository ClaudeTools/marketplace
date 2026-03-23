# Agents Guide

How to define and use Claude Code agents — custom personas with scoped tool access and specific expertise.

## Table of Contents

- [Overview](#overview)
- [Agent definition format](#agent-definition-format)
- [Frontmatter schema](#frontmatter-schema)
- [Design patterns](#design-patterns)
- [Role description design](#role-description-design)
- [Model selection guidance](#model-selection-guidance)
- [How agents are invoked](#how-agents-are-invoked)
- [Real examples](#real-examples)
- [Gotchas](#gotchas)
- [Verification checklist](#verification-checklist)

---

## Overview

Agents are markdown files that define specialized personas Claude Code can invoke as subagents. Each agent has a role description, optional tool restrictions, and an optional model override. Agents are invoked via the `Agent` tool with a `subagent_type` parameter.

Agent definitions live in `plugin/agents/` (for plugin-bundled agents) or `.claude/agents/` (for project-specific agents).

---

## Agent definition format

An agent is a single markdown file with YAML frontmatter and a body containing the role description:

```markdown
---
name: architect
description: Architecture review and planning agent. Invoke for design decisions and impact analysis.
disallowedTools:
  - Edit
  - Write
  - NotebookEdit
model: opus
---

You are an architecture agent. Analyse the codebase structure and propose changes.
Read widely before recommending — use Grep, Glob, and Read to understand the full picture.
Do not modify any files. Output your analysis with: current state assessment,
proposed changes with rationale, impact analysis, and migration path.
```

---

## Frontmatter schema

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Agent identifier. Should match the filename (without `.md`). |
| `description` | Yes | When to invoke this agent. Used by the parent agent to decide whether to spawn it. |
| `disallowedTools` | No | List of tools the agent cannot use. Useful for creating read-only or scoped agents. |
| `model` | No | Force a specific model: `opus`, `sonnet`, or `haiku`. Omit for the session default. |

---

## Design patterns

### Read-only agents

The most common pattern. Restrict the agent from modifying files by disallowing Edit, Write, and NotebookEdit. This is useful for review, analysis, and research tasks where modifications are unwanted.

From `plugin/agents/architect.md`:

```yaml
disallowedTools:
  - Edit
  - Write
  - NotebookEdit
model: opus
```

The architect agent can read the entire codebase, run grep searches, and execute bash commands for analysis, but cannot change any files. This makes it safe to invoke without worrying about unintended modifications.

From `plugin/agents/code-reviewer.md`:

```yaml
disallowedTools:
  - Edit
  - Write
  - NotebookEdit
model: sonnet
```

The code reviewer uses a lighter model (sonnet) because review tasks are less demanding than architectural analysis. It focuses on correctness, security, performance, and maintainability — producing structured findings without modifying code.

### Research agents

Agents that gather information from external sources. They typically have write restrictions and focus on web search and documentation retrieval.

From `plugin/agents/researcher.md`:

```yaml
disallowedTools:
  - Edit
  - Write
  - NotebookEdit
model: sonnet
```

The researcher uses WebSearch, WebFetch, and documentation tools to collect verified information. The role description emphasizes verifying claims against multiple sources and being explicit about what was and was not verified.

### Full-access agents

Agents that can read and modify files. These need careful role descriptions to scope their behavior.

From `plugin/agents/test-writer.md`:

```yaml
model: sonnet
```

The test-writer has no `disallowedTools` — it needs Edit and Write to create test files. The role description constrains its behavior: follow existing test patterns, use the project's test framework, run tests to verify they pass.

### Scoped agents

When an agent should only use specific tools, disallow everything else. This is less common but useful for highly constrained tasks:

```yaml
disallowedTools:
  - Bash
  - Edit
  - Write
  - NotebookEdit
  - WebSearch
  - WebFetch
```

This creates an agent that can only read files and search the codebase — no execution, no modification, no external access.

---

## Role description design

The body of the agent file is a role description that shapes the agent's behavior. Effective role descriptions share these qualities:

### Start with identity

Begin with "You are a [role] agent." This sets the behavioral frame immediately.

```markdown
You are an architecture agent.
```

```markdown
You are a code reviewer.
```

```markdown
You are a research agent.
```

### Specify methodology, not just outcome

Tell the agent HOW to approach the task, not just what to produce:

```markdown
Read widely before recommending — use Grep, Glob, and Read to understand
the full picture. Consider trade-offs explicitly: performance vs maintainability,
simplicity vs flexibility, consistency vs optimality.
```

```markdown
Verify claims against multiple sources — do not trust a single source.
Be explicit about what you verified and what you could not verify.
```

### Define output format

Specify what the agent should produce:

```markdown
Output your analysis with: current state assessment, proposed changes
with rationale, impact analysis (files affected, risks), and migration path.
```

```markdown
Output findings in structured format with file:line references.
Focus on real issues, not style nitpicks. Always include positive
observations about what was done well.
```

### Include behavioral constraints

Add constraints that prevent common failure modes:

```markdown
Do not modify any files.
```

```markdown
Follow existing test patterns in the project — read existing test files
first to match the style, framework, and conventions.
```

```markdown
Do not write tests that only assert the function exists.
```

---

## Model selection guidance

Choose the model based on the task's cognitive demands:

| Model | Best for | Trade-off |
|---|---|---|
| `opus` | Architecture analysis, complex reasoning, design decisions | Slowest, most expensive, highest quality |
| `sonnet` | Code review, research, test writing, most everyday tasks | Good balance of speed and quality |
| `haiku` | Simple data extraction, formatting, lightweight tasks | Fastest, cheapest, lower quality on complex reasoning |

If omitted, the agent uses the session's default model.

Use `opus` sparingly — only for tasks where the quality difference justifies the cost and latency. Most review and generation tasks work well with `sonnet`.

---

## How agents are invoked

Agents are invoked through the `Agent` tool. The parent agent (or the user) specifies:

- `subagent_type`: The agent name (matching the frontmatter `name` field)
- A task description for the subagent to execute

The subagent runs in its own context with the specified tool restrictions and model. It can read the same codebase but cannot see the parent's conversation history.

### Spawning from skills

Skills can delegate work to agents to keep the main context clean:

```markdown
## Phase 1: Research

Spawn a researcher subagent to gather API documentation:
Use the Agent tool with subagent_type "researcher" and the task
"Research the Stripe API v3 webhooks documentation. Focus on
event types, signature verification, and retry behavior."
```

### Spawning from hooks

The `SubagentStart` and `SubagentStop` hooks fire when subagents are spawned and complete. These are useful for providing subagent-specific context (like codebase indexes) and validating subagent output quality.

---

## Real examples from this plugin

### architect.md — Read-only, heavy reasoning

Uses `opus` model for high-quality architectural analysis. Disallows all write tools. Instructs the agent to read broadly before making recommendations and consider trade-offs explicitly.

### code-reviewer.md — Read-only, structured output

Uses `sonnet` for efficient review. Disallows write tools. Produces structured findings with file:line references. Includes a balance directive: focus on real issues, include positive observations.

### researcher.md — Read-only, external sources

Uses `sonnet` for external research. Disallows write tools. Emphasizes source verification and explicit uncertainty. Focuses on current documentation, known issues, and breaking changes.

### test-writer.md — Full access, pattern-following

Uses `sonnet` with no tool restrictions. Reads existing tests first to match project conventions. Runs generated tests to verify they pass. Focuses on edge cases and error paths, not trivial existence assertions.

---

## Gotchas

1. **Name must match filename.** The `name` field should match the `.md` filename (without extension). `architect.md` should have `name: architect`.

2. **disallowedTools uses exact tool names.** Use `Edit`, not `edit`. Use `NotebookEdit`, not `notebook-edit`. Check the exact tool name Claude Code uses.

3. **Subagents cannot see parent context.** A subagent starts fresh — it does not inherit the parent's conversation history, loaded skills, or in-memory state. Provide all necessary context in the task description.

4. **Model selection affects cost and latency.** An `opus` agent is significantly slower and more expensive than `sonnet`. Use `opus` only when the quality difference matters for the specific task.

5. **Write access does not mean the agent should write freely.** Even full-access agents need behavioral constraints in their role description. The test-writer can write files but is constrained to follow existing patterns and verify tests pass.

6. **Agent files in plugin/agents/ are plugin-wide.** They are available in every project that installs the plugin. For project-specific agents, put them in `.claude/agents/` instead.

7. **Keep role descriptions concise.** The entire agent file loads into the subagent's context. A 50-line role description wastes tokens that the subagent needs for its actual task. Aim for 5-15 lines of focused instructions.

8. **SubagentStop hooks validate output.** The `verify-subagent-independently.sh` hook runs when any subagent completes. It can inspect the subagent's output and flag quality issues. Keep this in mind when designing agents that produce structured output.

---

## Verification checklist

Before considering an agent complete:

- [ ] `name` in frontmatter matches the filename (without `.md`)
- [ ] `description` clearly states when to invoke this agent
- [ ] `disallowedTools` is set appropriately (read-only agents should disallow Edit/Write/NotebookEdit)
- [ ] `model` is set based on task complexity (default to sonnet unless opus-level reasoning is needed)
- [ ] Role description starts with identity ("You are a...")
- [ ] Methodology is specified, not just outcome
- [ ] Output format is defined
- [ ] Behavioral constraints prevent common failure modes
- [ ] Agent file is in `plugin/agents/` (plugin-wide) or `.claude/agents/` (project-specific)
- [ ] Role description is concise (under 15 lines)
- [ ] Tested by invoking via the Agent tool with realistic task descriptions

See `references/skills-guide.md` if the agent is spawned by a skill. See `references/hooks-guide.md` for SubagentStart/SubagentStop hook details.
