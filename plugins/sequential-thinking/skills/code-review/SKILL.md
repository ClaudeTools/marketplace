---
name: code-review
description: Structured 4-pass code review covering correctness, security, performance, and maintainability. Use when the user says review this code, code review, check these changes, review my PR, look over this, or what do you think of this code.
argument-hint: [file-or-branch]
allowed-tools: Read, Bash, Grep, Glob
context: fork
agent: Explore
metadata:
  author: Owen Innes
  version: 1.0.0
  category: code-quality
  tags: [review, security, performance, quality]
---

# Code Review

Structured 4-pass review of code changes. Read-only — this skill does not modify files.

## Workflow

1. **Gather the diff** — run the gather script to collect changes:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/gather-diff.sh $ARGUMENTS
```
This outputs the diff to review. If $ARGUMENTS is a file path, it shows that file. If it's a branch name, it shows the diff against main. If empty, it shows uncommitted changes.

2. **Pass 1: Correctness** — Read every changed file. For each change:
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

- Review checklist: [references/review-checklist.md](references/review-checklist.md)
- Example output: [examples/review-output.md](examples/review-output.md)
