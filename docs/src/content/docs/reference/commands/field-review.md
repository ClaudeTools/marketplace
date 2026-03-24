---
title: "/field-review"
description: "Field review of the claudetools plugin — reports on hook performance, false positives, bugs, and gaps from real session data."
---
Field review of the claudetools plugin itself — hooks, validators, skills performance, false positives, bugs, gaps, and praise. Generates a local report and optionally submits a sanitized summary to cross-install telemetry.

## Invocation

```
/field-review [--days N] [--submit]
```

**Arguments:**
- `--days N` — lookback window in days (default: 30)
- `--submit` — submit sanitized JSON summary to telemetry without asking

## Workflow

### Phase 1: Data Collection
Run `collect-metrics.sh` to gather hook outcomes, failure rates, threshold status, and changelog of recent plugin changes.

### Phase 2: Reflection
Reflect on experience with each component: hooks & validators, skills, codebase-pilot, memory system, telemetry, overall developer experience. Depth matters more than coverage — a single well-documented false positive is worth more than a list of vague complaints.

### Phase 3: Report
Save a full markdown report to `.claude/plugins/feedback/claudetools-review-{date}.md` covering: overall assessment, what works well, issues found (with component, severity, what happened, what should have happened), and prioritized recommendations.

### Phase 4: Submission Summary
Generate a sanitized JSON to `.claude/plugins/feedback/claudetools-review-{date}.json`. Contains NO file paths, NO code snippets, NO project names — only component names, categories, and generic descriptions.

### Phase 5: Optional Submission
Submit if `--submit` was passed or user confirms when asked:
```bash
bash .../submit-feedback.sh .claude/plugins/feedback/claudetools-review-{date}.json
```

## Quick example

```
/field-review --days 7
```

**Claude responds:**

```
Field Review — last 7 days

## Overall Assessment
Plugin is performing well. One false positive in blind-edit and a gap in
test coverage detection. No critical issues.

## What Works Well
- dangerous-bash catching rm -rf reliably (7 blocks, 0 false positives this week)
- secrets validator blocking exposed API keys in 2 separate sessions
- codebase-pilot symbol search accurate and fast on this TypeScript project

## Issues Found

  Component:  blind-edit validator
  Severity:   low
  What happened:   Warned on an edit to tsconfig.json that had been read
                   earlier in the session (read was in a compressed context block)
  Should have:     Allowed — file was in context
  Recommendation:  Widen the "already read" detection window

## Recommendations (prioritized)
1. Investigate blind-edit false positive rate on config files
2. Add test run detection for pytest (currently only detects npm test, jest)

Report saved to .claude/plugins/feedback/claudetools-review-2026-03-25.md
Submit? [y/N]
```

## Examples

```
/field-review
/field-review --days 7
/field-review --submit
/field-review --days 14 --submit
```

## Notes

- The full markdown report stays local — be as project-specific as needed.
- The JSON summary is sanitized for remote submission.
- If no metrics data exists, proceed with qualitative observations only.
