---
title: "Improving Plugin"
description: "Improving Plugin — claudetools documentation."
---
Run a full autonomous self-improvement loop — collect data, verify prior fixes, analyze, prioritize, implement, measure after-state, and log. Every change is measured: improvements are kept, regressions are caught and reverted.

**Trigger:** Use when the user says "improve", "self-improve", "improvement loop", "iterate", or "optimize the plugin".

**Invocation:** `/improving-plugin [--dry-run] [--category CATEGORY]`

---

## Arguments

| Flag | Effect |
|------|--------|
| `--dry-run` | Run Phases 1-4 only — report findings and baseline without implementing |
| `--category CATEGORY` | Filter to only findings in the specified category |

---

## Core Principle

Every iteration: **Measure → Change → Re-Measure → Keep or Revert**

---

## Phases

### Phase 1: Data Collection + Baseline Snapshot
- Run `collect-all-data.sh` (7-day window by default) — session metrics, hook outcomes, top failing tools, threshold status, remote telemetry, remote feedback, memory files, changelog, prior improvements.
- Run `capture-snapshot.sh` to record BEFORE numbers: `local_allow_rate`, per-hook block/warn rates, `avg_failures`, `avg_churn`, remote stats.

### Phase 2: Verify Prior Changes
- Check consumed findings registry for entries with `status: pending_validation`.
- Re-measure each metric; classify as VALIDATED, REGRESSED, or INCONCLUSIVE.
- Revert regressions before proceeding.

### Phase 3: Triage Findings
- Filter out already-consumed findings.
- Score remaining findings by impact (affect rate × session frequency × remote multiplier).
- Select top 3 findings. In `--dry-run`, stop here and report.

### Phase 4: Plan Changes
- Map each finding to a concrete change type: threshold adjustment, prompt edit, script fix, or new hook.
- Document the before/after for each planned change.

### Phase 5: Implement
- Apply changes to hook scripts, threshold files, or prompt configurations.
- Record each change in the consumed findings registry.

### Phase 6: Measure After-State
- Run `capture-snapshot.sh` again.
- Compare AFTER to BEFORE numbers.
- Revert any change where the metric moved in the wrong direction.
- Log final outcome (kept/reverted/partial) to improvement history.

---

## Example Invocations

```
/improving-plugin
/improving-plugin --dry-run
/improving-plugin --category hooks
/improving-plugin --category thresholds
```

---

## Related Components

- **evaluating-safety skill** — run training tests before/after to validate behavioral changes
- **scripts/collect-all-data.sh** — data collection entry point
- **scripts/capture-snapshot.sh** — before/after measurement
- **Remote telemetry** — fleet-wide data from all plugin installs, highest priority signal
