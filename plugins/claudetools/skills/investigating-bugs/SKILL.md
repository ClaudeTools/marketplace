---
name: investigating-bugs
description: Evidence-based debugging workflow that enforces REPRODUCE, OBSERVE, HYPOTHESIZE, VERIFY, FIX, CONFIRM. Use when the user says debug this, fix this bug, why is this failing, this is broken, not working, unexpected behaviour, or error.
argument-hint: [error-description]
allowed-tools: Read, Bash, Grep, Glob, Edit, Write
metadata:
  author: Owen Innes
  version: 1.0.0
  category: debugging
  tags: [debug, fix, investigate, evidence]
---

# Investigating Bugs

Evidence-based debugging. Every fix requires evidence. No guessing.

## The Protocol

Follow these steps in order. Do not skip steps. Do not jump to fixing without evidence.

### Step 1: REPRODUCE
Gather the error context:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/gather-diagnostics.sh $ARGUMENTS
```
Then reproduce the bug:
- Run the failing command/test/endpoint
- Capture the exact error output
- If the bug cannot be reproduced, say so and ask for more context

### Step 2: OBSERVE
Read the relevant code and understand what is happening:
- Read the file(s) where the error occurs
- Check recent changes: `git log --oneline -10 -- {file}`
- Read any related test files
- Check logs if available

### Step 3: HYPOTHESIZE
Before writing any fix, state your hypothesis:
- "The bug is caused by X because Y (evidence: Z)"
- If you have multiple hypotheses, rank them by likelihood
- Each hypothesis must reference specific evidence (error message, line number, log output)

### Step 4: VERIFY
Test your hypothesis before fixing:
- Add diagnostic logging if needed (temporary, remove later)
- Run targeted commands to confirm the root cause
- If the hypothesis is wrong, go back to Step 2

### Step 5: FIX
Now implement the fix:
- Fix the root cause, not the symptom
- Add or update a test that catches this specific bug
- Remove any diagnostic logging added in Step 4

### Step 6: CONFIRM
Verify the fix works:
- Run the previously-failing command — it should pass
- Run the full test suite — no regressions
- Run typecheck — no new errors

## Two-Strike Rule

If your first fix attempt does not resolve the bug:
1. Stop and re-read the error output carefully
2. Re-examine your hypothesis — was the root cause correct?
3. If your second fix attempt also fails, step back entirely:
   - Add more diagnostic logging
   - Reproduce again with verbose output
   - Form a new hypothesis from scratch

Do not attempt a third fix without fresh evidence.
