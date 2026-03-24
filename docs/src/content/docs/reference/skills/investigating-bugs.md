---
title: "Investigating Bugs"
description: "Investigating Bugs — claudetools documentation."
---
Evidence-based debugging that enforces a strict six-step protocol. No guessing, no assumptions — every fix must have concrete evidence.

**Trigger:** Use when the user says "debug this", "fix this bug", "why is this failing", "this is broken", "not working", or "unexpected behaviour".

**Invocation:** `/investigating-bugs [error-description]`

---

## The Protocol

Steps must be followed in order. Do not skip to fixing without evidence.

### Step 1: REPRODUCE
Run diagnostics, then reproduce the failing command/test/endpoint. Capture the exact error output. If the bug cannot be reproduced, say so and ask for more context.

### Step 2: OBSERVE
Read the relevant source files. Check recent changes with `git log --oneline -10 -- {file}`. Read related test files and available logs.

### Step 3: HYPOTHESIZE
Before writing any fix, state the hypothesis explicitly:
> "The bug is caused by X because Y (evidence: Z)"

Rank multiple hypotheses by likelihood. Each must cite specific evidence (error message, line number, log output).

### Step 4: VERIFY
Test the hypothesis before fixing. Add diagnostic logging if needed (mark as temporary). If the hypothesis is wrong, return to Step 2.

### Step 5: FIX
Fix the root cause, not the symptom. Add or update a test that catches this specific bug. Remove any diagnostic logging.

### Step 6: CONFIRM
Run the previously-failing command (should now pass), run the full test suite (no regressions), run typecheck (no new errors).

---

## Two-Strike Rule

If the first fix attempt fails:
1. Stop and re-read the error output carefully.
2. Re-examine the hypothesis — was the root cause correct?
3. If the second attempt also fails, step back entirely: add more diagnostic logging, reproduce again with verbose output, form a new hypothesis from scratch.

Do not attempt a third fix without fresh evidence.

---

## Example Invocations

```
/investigating-bugs TypeError: Cannot read property 'id' of undefined
/investigating-bugs The payment webhook is not being received
/investigating-bugs Tests pass locally but fail in CI
```

---

## Related Components

- **exploring-codebase skill** — use to locate relevant files before Step 2
- **debugging-discipline rule** — enforces the two-strike rule and evidence requirement across all sessions
- **codebase-pilot CLI** — `find-symbol`, `file-overview` for locating code during OBSERVE phase
