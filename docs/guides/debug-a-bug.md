---
title: Debug a Bug
parent: Guides
nav_order: 1
---

# Debug a Bug

Use the investigating-bugs skill to track down and fix any error using a structured, evidence-based protocol that prevents guessing and dead-end fixes.
{: .fs-6 .fw-300 }

## What you need
- claudetools installed
- A reproducible error, failing test, or unexpected behaviour to investigate

## Steps

### 1. Describe the error to Claude

Tell Claude what is broken. Include the error message, the command that fails, or a description of the unexpected behaviour.

```
fix this bug: TypeError: Cannot read properties of undefined (reading 'id')
```

The investigating-bugs skill activates automatically when you use words like "debug", "fix", "why is this failing", "not working", or "unexpected behaviour".

### 2. REPRODUCE — confirm the bug exists

Claude runs a diagnostics script then attempts to reproduce the exact failure:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/investigating-bugs/scripts/gather-diagnostics.sh
```

If the bug cannot be reproduced, Claude asks for more context before continuing. Never skip this step — a fix for an unreproduced bug is a guess.

### 3. OBSERVE — read the relevant code

Claude reads the file where the error occurs, checks recent git history for that file, and reads any related test files:

```bash
git log --oneline -10 -- path/to/file.ts
```

This surfaces recent changes that may have introduced the bug without requiring you to do the archaeology yourself.

### 4. HYPOTHESIZE — state the root cause before fixing

Before touching any code, Claude writes out a hypothesis:

> "The bug is caused by X because Y (evidence: Z)"

Multiple hypotheses are ranked by likelihood. Each one references specific evidence — an error message, a line number, a log output. If Claude cannot point to evidence, it goes back to OBSERVE.

### 5. VERIFY — test the hypothesis

Claude adds diagnostic logging or runs targeted commands to confirm the root cause before fixing anything. If the hypothesis is wrong, it returns to OBSERVE and forms a new one.

### 6. FIX — address the root cause

Claude implements the fix targeting the root cause, not the symptom. It also adds or updates a test that catches this specific bug, so the same failure cannot regress silently.

### 7. CONFIRM — verify the fix works

```bash
# Run the previously-failing command
npm test -- --grep "auth"

# Run typecheck
npx tsc --noEmit
```

Claude runs the previously-failing command (it should now pass), runs the test suite to check for regressions, and runs typecheck. All three must pass before the fix is declared complete.

## What happens behind the scenes

- The **investigating-bugs skill** is triggered by keywords in your message (debug, fix, broken, error, etc.)
- The **gather-diagnostics.sh** script collects environment info, recent git log, and any available logs
- All six steps (REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY → FIX → CONFIRM) run in sequence — Claude cannot skip ahead
- The **two-strike rule** activates if the first fix fails: Claude re-reads the error carefully and re-examines the hypothesis before attempting a second fix. After two failed attempts, Claude adds more diagnostic logging and starts from scratch

## Tips

- Include the full stack trace, not just the error message — line numbers in the trace let Claude skip directly to OBSERVE
- If Claude's first hypothesis seems wrong to you, say so before it moves to VERIFY — it's faster to correct the hypothesis early
- For intermittent bugs, describe the conditions under which it occurs; Claude will adjust the REPRODUCE step accordingly
- The two-strike rule protects you from Claude spinning on incorrect fixes — trust it to restart with fresh evidence rather than forcing a third attempt

## Related

- [Exploring a Codebase](explore-a-codebase.md) — understand the code around a bug before diving in
- [Run a Security Audit](run-security-audit.md) — find security-class bugs proactively
- [Reference: investigating-bugs skill](../reference/skills.md)
