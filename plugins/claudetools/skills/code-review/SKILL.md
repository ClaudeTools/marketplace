---
name: code-review
description: >
  Structured 4-pass code review covering correctness, security, performance,
  and maintainability. Use when completing tasks, implementing major features,
  or before merging to verify work meets requirements.
argument-hint: "[file-or-directory-to-review]"
allowed-tools: Glob, Grep, LS, Read, NotebookRead, WebFetch, WebSearch
metadata:
  author: claudetools
  version: 1.0.0
  category: quality
  tags: [review, quality, security, correctness]
---

# Structured Code Review

4-pass review process: correctness → security → performance → maintainability.

## When to Use

- After completing a major implementation task
- Before merging a feature branch
- When asked to review code quality
- After a subagent finishes work

## Process

1. **Gather context**: Run `bash ${CLAUDE_SKILL_DIR}/scripts/gather-diff.sh` to collect the diff
2. **Pass 1 — Correctness**: Does the code do what it claims? Are edge cases handled?
3. **Pass 2 — Security**: OWASP top 10, injection risks, credential exposure
4. **Pass 3 — Performance**: Unnecessary allocations, N+1 queries, missing indexes
5. **Pass 4 — Maintainability**: Naming, structure, test coverage, documentation

See `${CLAUDE_SKILL_DIR}/references/review-checklist.md` for the full checklist.
See `${CLAUDE_SKILL_DIR}/examples/review-output.md` for example output format.
