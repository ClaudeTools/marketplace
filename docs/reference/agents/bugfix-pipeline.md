---
title: Bugfix Pipeline
parent: Agents
grand_parent: Reference
nav_order: 2
---

# Bugfix Pipeline

Full-cycle bug fix pipeline. Orchestrates reproduction, investigation, fix implementation, review, and confirmation.

## Purpose

Coordinates evidence-based bug resolution from reproduction through verified fix. Enforces a structured protocol that prevents fixing from description alone — every step must be grounded in observed evidence before proceeding to the next.

## Model

`sonnet`

## Tool Access

Full access: `Glob, Grep, LS, Read, Edit, Write, NotebookRead, NotebookEdit, Bash, WebFetch, WebSearch, TodoWrite, Agent, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet, KillShell, BashOutput`

## Workflow

### 1. Explore

Uses codebase-pilot to locate the affected area before touching anything:

```bash
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<error-source>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<affected-file>"
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-usages "<symbol>"
git log --oneline -20 -- <affected-file>
```

### 2. Investigate

Follows the `investigating-bugs` protocol:

- **Reproduce** — runs the failing command and captures exact error output. If not reproducible, stops and asks for more context.
- **Observe** — reads the actual code at the error location, checks git log for recent changes.
- **Hypothesize** — states the hypothesis clearly with supporting evidence. No guessing.
- **Verify** — writes a minimal test or assertion. If the hypothesis is disproved after 2 attempts (two-strike rule), re-instruments with logging before trying again.

### 3. Implement

Spawns an `implementing-features` teammate with the hypothesis, evidence, and exact `file:line` to change. The fix must address root cause, not symptoms.

### 4. Review

Runs a `code-reviewer` agent over the fix. Confirms the fix addresses the stated root cause and checks for regressions in related code paths.

### 5. Confirm

```bash
./tests/run-tests.sh --file <affected-area>
./tests/run-tests.sh <related-category>
```

The original failing test must now pass. Commits with a `fix:` conventional commit message.

## When to Use

- A bug needs structured, evidence-based resolution
- The cause is unclear and requires investigation
- The fix touches shared code that could regress other paths
- You want review built into the fix process

## Constraints

- Never fix from description alone — always reproduce first
- State the hypothesis before making any change
- Two-strike rule: re-instrument after two failed hypotheses
- Never mark done until the original failing test passes

## Example Usage

```
Use the bugfix-pipeline agent to fix the authentication token expiry bug reported in #234.
```
