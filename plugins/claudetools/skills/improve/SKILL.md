For full Build Mode creative workflow, read SKILL-FULL.md in this directory.

# Self-Improvement Loop (Compact)

> This is the compact version. For full creative workflow, invoke with `/improve build`

Run an autonomous improvement iteration on the claudetools plugin: collect data, verify prior fixes, analyze, implement, measure, log.

## Core Principle

Measure -> Change -> Re-Measure -> Keep or Revert. Every change is measured.

## Workflow

1. **Collect data + baseline**: `bash ${CLAUDE_SKILL_DIR}/scripts/collect-all-data.sh ${DAYS:-7}` then `bash ${CLAUDE_SKILL_DIR}/scripts/capture-snapshot.sh ${DAYS:-7} > /tmp/improve-baseline.json`
2. **Verify prior fixes**: Check consumed findings registry for `pending_validation` entries. Classify as VALIDATED / HOLDING / REGRESSED.
3. **Analyze + dedup**: Identify issues, assign categories, check against consumed-findings.jsonl to skip already-fixed items.
4. **Prioritize**: Regressions first, then by installs affected, severity, frequency. Select top 1-3.
5. **Implement**: Targeted edits in `plugin/` source. Syntax check: `bash -n {file}`.
6. **After-snapshot**: `bash ${CLAUDE_SKILL_DIR}/scripts/capture-snapshot.sh ${DAYS:-7} > /tmp/improve-after.json` — compare before vs after. Revert regressions.
7. **Log**: `bash ${CLAUDE_SKILL_DIR}/scripts/log-improvement.sh "{category}" "{description}" "{sources}" "{scope}" "{baseline}" "{finding_key}"`

## Categories

`hook-coverage`, `noise-reduction`, `friction-reduction`, `error-messages`, `progressive-disclosure`, `telemetry-quality`, `test-gaps`, `safety-corpus`, `skill-quality`, `prompt-quality`, `regression-fix`, `semantic-intelligence`, `no-op`

## Key Constraints

- Never undo prior threshold tuning without strong evidence.
- Dedup against consumed-findings.jsonl — skip `validated` and `pending_validation` entries.
- Revert any change that causes metric regression.
- Log every iteration, including no-ops with verification summary.
- `--dry-run`: phases 1-4 only (report without implementing).
- `--category CAT`: filter to one category.

## Decision Rules

| After-state | Action |
|-------------|--------|
| IMPROVED | Keep, log with before/after values |
| SAME (structural change) | Keep, log as `pending_validation` |
| REGRESSED | Revert immediately, log as failed attempt |

## Scripts

| Script | Use |
|--------|-----|
| `scripts/collect-all-data.sh` | Gather metrics, hook outcomes, remote telemetry, feedback |
| `scripts/capture-snapshot.sh` | Snapshot current system health as JSON |
| `scripts/log-improvement.sh` | Record iteration result to improvement log |
