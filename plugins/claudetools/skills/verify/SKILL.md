---
name: verify
description: >
  Verify implementation actually works before claiming completion. Run commands,
  read output, check exit codes. Evidence before assertions. Use before committing,
  creating PRs, or declaring any task done.
argument-hint: "[what to verify]"
allowed-tools: Read, Bash, Glob, Grep, AskUserQuestion
metadata:
  author: claudetools
  version: 1.0.0
  category: workflow
  tags: [verification, testing, evidence, quality]
---

# Verify Before Claiming Done

> IRON LAW: No completion claims without fresh verification evidence. Run the
> command. Read the output. Check the exit code. Then — and only then — say it works.

## The Protocol

### Step 1: Identify what to verify

For every claim you're about to make, identify the verification command:

| Claim | Verification |
|-------|-------------|
| "Tests pass" | Run the test command. Read the output. Count pass/fail. |
| "Build succeeds" | Run the build command. Check exit code. |
| "Bug is fixed" | Reproduce the original symptom. Confirm it's gone. |
| "Feature works" | Execute the feature. Observe the result. |
| "No regressions" | Run the full relevant test suite. |

### Step 2: Run the command

Actually run it. Not "it should work." Not "based on my changes." RUN IT.

### Step 3: Read the full output

Don't skim. Don't assume. Read the output. Check:
- Exit code (0 = success, anything else = failure)
- Warnings (not just errors)
- Test counts (expected vs actual)
- Any unexpected output

### Step 4: Report with evidence

```
✓ Tests: 34/34 passing (ran `npm test`, exit code 0)
✓ Build: clean (ran `npm run build`, no errors)
✓ Symptom: resolved (reproduced original error, confirmed fix)
```

NOT: "Should be working now." NOT: "Looks correct." NOT: "I believe this fixes it."

## Forbidden Phrases

These phrases mean you haven't verified:
- "should work"
- "looks correct"
- "appears to"
- "I believe this fixes"
- "probably works"
- "seems to work"
- "I think this is right"

If you catch yourself writing any of these, STOP and run the verification command.
