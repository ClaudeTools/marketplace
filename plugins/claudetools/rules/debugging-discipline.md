---
paths:
  - "**/*"
---

# Debugging and Research Discipline

## Never Fix Based on Assumptions
You MUST have concrete evidence before writing ANY fix. Evidence = error messages, log output, network traces, reproduced behavior. NOT "I think the issue might be..."

Workflow: REPRODUCE → OBSERVE → HYPOTHESIZE → VERIFY → FIX → CONFIRM.

If you can't reproduce: add diagnostic logging first, deploy it, have the user reproduce, read the logs, THEN fix.

## Two-Strike Rule
If your fix doesn't work after 2 attempts, STOP. You are guessing. Add comprehensive logging and start over with evidence.

## Research Before Code
When working with external services, APIs, libraries, or platforms:
1. Search current docs (WebSearch, Context7, platform docs) BEFORE writing code.
2. Never assume API formats, method signatures, or platform behavior from training data.
3. When an external service returns an error, search for that exact error FIRST.

When you don't know something: SEARCH FOR IT. Do not guess, trial-and-error, or say "this should work" without checking.

When the two-strike rule triggers, invoke the investigating-bugs skill for structured evidence-based debugging.
