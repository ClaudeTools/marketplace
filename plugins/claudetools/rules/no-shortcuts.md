---
paths:
  - "**/*"
---

# No Shortcuts

## Implementation
- No stubs, TODOs, placeholders, or `throw new Error('Not implemented')`. Implement fully or tell the user you can't.
- No `as any` abuse, `@ts-ignore`, or empty function bodies. These are type-safety escape hatches, not solutions.
- No mocks or fake data outside test files. No re-exports that add no logic. No wrapper classes that just forward calls.
- Never trust "build passes" or "tests pass" as proof of completion. Builds pass with empty files. Tests pass against mocks.

## Verification
- After writing code: re-read the file and confirm real logic exists.
- After fixing a bug: demonstrate with real output, not "it should work now."
- After deploying: hit the endpoint with real data and show the response.
- After completing a task: show evidence of behavior, not just passing gates.
- Never dismiss LSP diagnostics, type errors, or lint warnings as "stale" or "transitional." If the file on disk has errors, it has errors. Investigate, don't rationalize.
- Never trust a subagent's self-reported "typecheck passes" or "all tests pass." Run the check independently.

## Scope
- Only modify files directly related to the current request. Mention unrelated issues but don't fix them unless asked.
- Deliver what was asked. Don't simplify, reduce scope, or substitute an easier alternative without approval.
- Before reporting done: re-read the original request, compare each requirement, list any gaps explicitly.
- Don't rename files, restructure directories, or add dependencies unless that's the task.

## Assume Broken
- AI agents cut corners, create stubs, and mistake compilation for completion. Assume all prior agent work is broken until verified with real runtime behavior.
- Quality gates (typecheck, tests, deploys) produce false positives. They prove syntax, not function. A passing build with empty components is worthless.
- When inheriting work from a previous agent: read the actual code, don't trust the agent's summary.
- When an agent reports "done, verified" — verify it yourself anyway.

