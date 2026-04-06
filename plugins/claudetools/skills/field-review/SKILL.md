---
name: field-review
description: >
  Field review of the claudetools plugin itself (NOT code review). Reports on
  hooks, validators, and skills performance — false positives, bugs, gaps,
  praise. Use when evaluating plugin health or reporting on hook behavior.
argument-hint: "[area-to-review: hooks|validators|skills|all]"
allowed-tools: Glob, Grep, LS, Read, Bash, WebFetch, WebSearch
metadata:
  author: claudetools
  version: 1.0.0
  category: meta
  tags: [field-review, plugin-health, metrics, feedback]
---

# Field Review

Evaluate claudetools plugin health from real-world usage data.

## When to Use

- After a session with noticeable hook issues (false positives, slowness)
- Periodically to assess plugin health
- When reporting bugs or praise to the plugin maintainer

## Process

1. **Collect metrics**: Run `bash ${CLAUDE_SKILL_DIR}/scripts/collect-metrics.sh`
2. **Review findings**: Analyze hook outcomes, false positive rates, latency
3. **Submit feedback**: Run `bash ${CLAUDE_SKILL_DIR}/scripts/submit-feedback.sh` with findings
