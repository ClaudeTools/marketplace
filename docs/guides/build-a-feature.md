---
title: Build a Feature
parent: Guides
nav_order: 2
---

# Build a Feature

Use the feature-pipeline agent to take a feature from idea to verified delivery — covering codebase exploration, planning, parallel implementation, code review, and final verification.
{: .fs-6 .fw-300 }

## What you need
- claudetools installed
- A feature description (rough or detailed — the pipeline handles enrichment)

## Steps

### 1. Create a task for the feature

Before spawning the pipeline, create a persistent task so the work is tracked across the session:

```
/managing-tasks new Add CSV export to the invoices page
```

The task system enriches the description using codebase context, adds acceptance criteria, and identifies the files involved. Review the generated task and confirm it before proceeding.

### 2. Spawn the feature pipeline

With the task created, start the feature-pipeline agent:

```
/claudetools:feature-pipeline <task description or task ID>
```

The pipeline orchestrates the entire workflow. You do not need to manage individual steps.

### 3. EXPLORE — understand the codebase first

The pipeline runs codebase-pilot commands to map the area where the feature will land:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "invoices"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "src/pages/invoices.tsx"
```

The pipeline reads the relevant code before forming any plan. Nothing is assumed.

### 4. PLAN — break the feature into reviewable steps

Using the codebase knowledge from EXPLORE, the pipeline structures the implementation into discrete steps with dependencies and ordering. It identifies cross-cutting concerns (auth, logging, error handling) and documents the expected interface before writing any code.

Review the plan when it is presented. You can ask for changes before implementation begins.

### 5. IMPLEMENT — teammates build in parallel

The pipeline spawns implementing-features teammates, one per logical unit:

- One teammate for the data layer
- One teammate for the UI layer
- One teammate for tests

Teammates coordinate shared decisions via the agent-mesh CLI:

```bash
node ${CLAUDE_PLUGIN_ROOT}/agent-mesh/cli.js context --set "csv-format" "RFC 4180"
```

You do not need to coordinate them manually.

### 6. REVIEW — code-reviewer checks the output

After implementation, the pipeline runs a code-reviewer agent over all changed files. Every finding comes with a file:line reference. Blocking findings must be resolved before the pipeline proceeds.

### 7. VERIFY — typecheck and targeted tests

```bash
npx tsc --noEmit
./tests/run-tests.sh --file invoices
```

The pipeline runs typecheck and tests scoped to the changed files. All checks must pass before the feature is declared complete.

## What happens behind the scenes

- **feature-pipeline agent** orchestrates the entire lifecycle — you interact with it as a single agent
- **codebase-pilot CLI** indexes the project and answers structural questions without reading every file
- **TeamCreate** spawns implementing-features teammates in parallel for independent work units
- **agent-mesh CLI** passes shared decisions between teammates so they stay consistent
- **code-reviewer agent** runs a 4-pass review (correctness, security, performance, maintainability)
- **run-tests.sh** only runs tests related to changed files — never the full suite unless you ask

## Tips

- If the feature is large, ask the pipeline to decompose it into subtasks first: `/managing-tasks decompose <task-id>`
- You can interrupt after PLAN and before IMPLEMENT if the plan needs revision — the pipeline waits for your confirmation
- For features touching auth, database schema, or API contracts, flag this in your initial description so the pipeline highlights those concerns in the plan
- The pipeline never skips VERIFY — if tests fail, fix them before declaring the feature done

## Related

- [Manage Tasks](manage-tasks.md) — create and track feature tasks
- [Review Code](review-code.md) — run a manual review on the output
- [Coordinate Agents](coordinate-agents.md) — understand how teammates share decisions
