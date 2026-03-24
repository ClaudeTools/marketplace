---
title: "Review Code"
description: "Review Code — claudetools documentation."
---
Use the `/code-review` command to run a structured 4-pass review covering correctness, security, performance, and maintainability — on a branch, a file, or uncommitted changes.


## What you need
- claudetools installed
- Code to review: a git branch, a file path, or uncommitted changes in the working tree

## Steps

### 1. Choose your scope

The `/code-review` command accepts three kinds of input:

**Review a branch** (diff against main):
```
/code-review feature/csv-export
```

**Review a specific file**:
```
/code-review src/pages/invoices.tsx
```

**Review uncommitted changes** (no argument):
```
/code-review
```

### 2. Claude gathers the diff

The review starts by running a gather script that collects the changes to review:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/code-review/scripts/gather-diff.sh [branch-or-file]
```

- If given a file path: shows that file's content
- If given a branch name: shows the diff against main
- If given nothing: shows all uncommitted changes

### 3. Pass 1 — Correctness

Claude reads every changed file and checks:
- Does the logic do what it claims?
- Are edge cases handled (null, empty, boundary values)?
- Are error paths complete (try/catch, error returns)?
- Do types match (no implicit any, correct return types)?

### 4. Pass 2 — Security

Claude scans for vulnerabilities:
- SQL injection (string interpolation in queries)
- XSS (unsanitised user input in HTML or JSX)
- Secret exposure (hardcoded keys, tokens, passwords)
- Path traversal (unsanitised file paths)
- Missing auth checks on sensitive routes

### 5. Pass 3 — Performance

Claude checks for:
- N+1 queries or unnecessary database calls
- Missing indexes for queried fields
- Unbounded loops or recursion
- Large allocations in hot paths
- Missing pagination on list endpoints

### 6. Pass 4 — Maintainability

Claude assesses code quality:
- Follows existing patterns in the codebase?
- Naming is clear and consistent?
- Duplication that should be extracted?
- Tests cover the changes?

### 7. Read the findings

Findings are grouped by severity:

```
## Code Review: feature/csv-export

### Critical (must fix)
- [src/api/export.ts:42] Raw SQL string interpolation — user input reaches query directly

### Important (should fix)
- [src/pages/invoices.tsx:88] Missing loading state — component renders null while fetching

### Suggestions (nice to have)
- [src/utils/csv.ts:15] extractRow duplicates logic from formatRow — consider extracting shared helper

### Positive
- Error boundaries correctly placed at route level
- TypeScript strict mode maintained throughout
```

Categories with no findings are omitted. The Positive section always appears.

## What happens behind the scenes

- The review is **read-only** — no files are modified
- All findings include a `file:line` reference so you can navigate directly to the issue
- The 4-pass structure ensures security and performance are never skipped even when the diff looks small

## Tips

- Run `/code-review` before every PR — catching issues locally is faster than in review
- For a branch review, the diff is computed against `main` — make sure your branch is rebased if main has advanced significantly
- If you want to review only security issues on a large diff, say "focus on Pass 2" after the review starts
- The Positive section is intentional — use it to reinforce patterns you want the team to repeat

## Related

- [Build a Feature](build-a-feature.md) — the feature-pipeline runs code-review automatically after implementation
- [Run a Security Audit](run-security-audit.md) — full codebase security scan, not just changed files
- [Reference: code-review skill](../reference/skills.md)
