# Code Review (Compact)

> This is the compact version. For full creative workflow, invoke with `/code-review build`

Structured 4-pass code review. Read-only — does not modify files.

## Workflow

1. **Gather diff**: `bash ${CLAUDE_SKILL_DIR}/scripts/gather-diff.sh $ARGUMENTS`
   - File path: shows that file. Branch name: diff against main. Empty: uncommitted changes.
2. **Pass 1 — Correctness**: Logic matches intent? Edge cases (null, empty, boundary)? Error paths complete? Types correct?
3. **Pass 2 — Security**: SQL injection, XSS, secret exposure, path traversal, missing auth checks.
4. **Pass 3 — Performance**: N+1 queries, missing indexes, unbounded loops, large allocations, missing pagination.
5. **Pass 4 — Maintainability**: Follows codebase patterns? Clear naming? Duplication? Test coverage?

## Output Format

```
## Code Review: {scope}

### Critical (must fix)
- [file:line] Description

### Important (should fix)
- [file:line] Description

### Suggestions (nice to have)
- [file:line] Description

### Positive
- What was done well
```

Skip empty severity sections. Always include Positive.

## Key Constraints

- Read-only. Do not modify any files.
- Read every changed file — do not review from diff alone.
- Cover all four passes in order.

## References

- `${CLAUDE_SKILL_DIR}/references/review-checklist.md`
- `${CLAUDE_SKILL_DIR}/examples/review-output.md`
