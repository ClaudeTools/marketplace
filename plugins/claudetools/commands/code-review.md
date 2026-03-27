---
description: Structured 4-pass code review covering correctness, security, performance, and maintainability.
argument-hint: "[file-or-branch]"
---

# Code Review

Structured 4-pass review of code changes. Read-only — this skill does not modify files.

## Workflow

1. **Gather the diff** — run the gather script to collect changes:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/code-review/scripts/gather-diff.sh $ARGUMENTS
```
This outputs the diff to review. If $ARGUMENTS is a file path, it shows that file. If it's a branch name, it shows the diff against main. If empty, it shows uncommitted changes.

2. **Scope the review** — After gathering the diff, assess its size. If the diff touches 5+ files or 200+ lines, use AskUserQuestion to let the user scope the review:

   - **Single-select** for review depth: derive options from the actual diff size. Label each with what it covers for THIS diff (e.g. "Quick — scan 3 changed controllers for obvious issues" vs "Deep — all 12 files including test changes, line-by-line").
   - **multiSelect** for pass selection (only if depth is not "quick"): list the 4 passes (Correctness, Security, Performance, Maintainability) and let the user deselect passes they don't care about for this review. Description for each should reference what's relevant in the actual diff (e.g. "Security — this diff adds 2 new API endpoints with user input").
   - **Skip the question** if the diff is small (<5 files, <200 lines) — just run all 4 passes.

3. **Pass 1: Correctness** — Read every changed file. For each change:
   - Does the logic do what it claims?
   - Are edge cases handled (null, empty, boundary values)?
   - Are error paths complete (try/catch, error returns)?
   - Do types match (no implicit any, correct return types)?

3. **Pass 2: Security** — Scan for vulnerabilities:
   - SQL injection (string interpolation in queries)
   - XSS (unsanitised user input in HTML/JSX)
   - Secret exposure (hardcoded keys, tokens, passwords)
   - Path traversal (unsanitised file paths)
   - Missing auth checks on sensitive routes

4. **Pass 3: Performance** — Check for performance issues:
   - N+1 queries or unnecessary database calls
   - Missing indexes for queried fields
   - Unbounded loops or recursion
   - Large allocations in hot paths
   - Missing pagination on list endpoints

5. **Pass 4: Maintainability** — Assess code quality:
   - Follows existing patterns in the codebase?
   - Naming is clear and consistent?
   - Duplication that should be extracted?
   - Tests cover the changes?

6. **Output findings** in this format:
```
## Code Review: {scope}

### Critical (must fix)
- [file:line] Description of issue

### Important (should fix)
- [file:line] Description of issue

### Suggestions (nice to have)
- [file:line] Description of improvement

### Positive
- What was done well
```

If no issues found in a category, skip it. Always include the Positive section.

## Reference files

- Review checklist: [${CLAUDE_PLUGIN_ROOT}/skills/code-review/references/review-checklist.md](references/review-checklist.md)
- Example output: [${CLAUDE_PLUGIN_ROOT}/skills/code-review/examples/review-output.md](examples/review-output.md)
