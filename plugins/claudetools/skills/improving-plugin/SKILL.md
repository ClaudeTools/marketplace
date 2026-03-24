---
name: improving-plugin
description: Run a full self-improvement loop — collect data, verify prior fixes, analyze, prioritize, capture baseline, implement, measure after-state, and log. Use when the user says improve, self-improve, improvement loop, iterate, or optimize the plugin.
argument-hint: [--dry-run] [--category CATEGORY]
allowed-tools: Read, Bash, Grep, Glob, Write, Edit, WebFetch
metadata:
  author: Owen Innes
  version: 2.0.0
  category: meta
  tags: [self-improvement, telemetry, autonomous, loop, before-after]
---

# Improving Plugin

Run a full autonomous improvement iteration with built-in before/after measurement. Every change is measured — improvements are kept, regressions are caught and reverted, duplicate work is prevented.

## Core Principle: Measure → Change → Re-Measure → Keep or Revert

Every iteration follows this discipline:
1. Capture a baseline snapshot of current system health
2. Verify that prior changes are still holding (detect regressions)
3. Identify new findings, filtering out already-consumed ones
4. Implement changes
5. Capture an after-snapshot and compare to baseline
6. Keep changes that improved metrics, revert changes that regressed

## Arguments

| Flag | Effect |
|---|---|
| `--dry-run` | Run Phases 1-4 only — report findings, priorities, and baseline without implementing |
| `--category CATEGORY` | Filter to only findings in the specified category |

## Phase 1: Data Collection + Baseline Snapshot

### 1a. Collect all data

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/collect-all-data.sh ${DAYS:-7}
```

Read the entire output. This is your evidence base. Key sections:

- **Session metrics**: Failure rates, churn rates. High churn (>3.0) = agents re-editing. High failures (>5 avg) = tools struggling.
- **Hook outcomes**: Block/warn rates per hook. >30% block = too aggressive. >50% FP = actively harmful.
- **Top failing tools**: Clusters suggest systematic issues (Edit failures = not reading first).
- **Threshold status**: Modified thresholds = prior tuning. Do not undo without strong evidence.
- **Recent non-allow events**: What is actively triggering now. Look for component clusters.
- **Remote telemetry**: Fleet-wide data across ALL installs. Fleet problems outrank local issues.
- **Remote feedback**: Field reviews with items, narratives (deep reasoning), component grades, and self-critiques from reviewing agents.
- **Memory files**: Project-specific feedback. Check if any feedback is unaddressed.
- **Changelog**: What recently changed — do not re-do recent work.
- **Prior improvements**: Last 10 iterations. Do not regress fixed issues.
- **Consumed findings registry**: Machine-parseable record of what was already addressed. Use this for deduplication (Phase 3).

### 1b. Capture baseline snapshot

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/capture-snapshot.sh ${DAYS:-7} > /tmp/improve-baseline.json
```

Read the snapshot. Note the key numbers you'll compare against later:
- `local_allow_rate` — overall system health percentage
- `hook_rates` — per-hook block/warn percentages
- `avg_failures` — average tool failures per session
- `avg_churn` — edit churn rate
- `remote_stats` — fleet-wide totals

These are your BEFORE numbers. Write them down — you'll need them in Phase 6.

## Phase 2: Verify Prior Changes

Before making any new changes, check that recent fixes are still holding.

Read the consumed findings registry from the data collection output. For each entry with `status: pending_validation`:

1. **Re-measure** the metric cited in the `baseline` field using current data from the Phase 1 output
2. **Classify** the result:
   - **VALIDATED** — the metric improved or held. The fix is working.
   - **HOLDING** — the metric is unchanged. The fix didn't help but didn't hurt.
   - **REGRESSED** — the metric worsened. The fix may have been reverted, or a new change broke it.

3. **Report** all verification results:
   ```
   Prior fix verification:
   ✓ noise-reduction:stop-gate — VALIDATED (42% warn → 12% warn)
   ✓ friction-reduction:deploy-gate — VALIDATED (20 blocks/24h → 0)
   ✗ hook-coverage:read-efficiency — REGRESSED (0 blocks → 15 blocks)
   ```

4. Any REGRESSED entry automatically becomes a `regression-fix` finding for Phase 3.

If there are no pending_validation entries, note "No prior fixes pending validation" and continue.

## Phase 3: Analysis + Deduplication

Analyze all collected data and identify issues. For each finding, assign exactly one category:

| Category | What it covers |
|---|---|
| `hook-coverage` | Missing hooks, new dangerous patterns to catch |
| `progressive-disclosure` | Message verbosity, multi-tier escalation, information overload |
| `error-messages` | Cryptic messages, missing context, unhelpful guidance |
| `noise-reduction` | High warn/block rates that are mostly false positives |
| `friction-reduction` | Hooks blocking legitimate work, false positives eroding trust |
| `telemetry-quality` | Missing data fields, incorrect event classification |
| `test-gaps` | Missing or insufficient test coverage |
| `safety-corpus` | New dangerous patterns, gaps in safety tests |
| `skill-quality` | Skill workflows that are unclear or incomplete |
| `prompt-quality` | Agent prompts or instructions that could be clearer |
| `regression-fix` | Something previously fixed has broken again |
| `semantic-intelligence` | Codebase indexing, language support improvements |
| `no-op` | System is healthy, no actionable findings |

For each finding, document:
1. **What the data shows** — cite specific numbers, event counts, rates, or feedback quotes
2. **Why it matters** — user impact (blocks work, creates noise, misses real issues)
3. **What should change** — the specific modification
4. **Finding key** — a dedup identifier as `{category}:{component}` (e.g., `noise-reduction:stop-gate`)
5. **Measurable baseline** — the current value of the metric this change targets (e.g., `42%-warn-rate`, `0-tests`)

### Deduplication rules

Check each finding's key against the consumed findings registry:
- **Key exists, status=validated**: SKIP — already fixed and holding. Unless new data shows the fix is insufficient, do not re-address.
- **Key exists, status=pending_validation**: SKIP — was recently fixed, not yet verified. Phase 2 will validate it next iteration.
- **Key exists, status=regressed**: PROMOTE to `regression-fix` — the prior fix broke. This gets priority.
- **Key does not exist**: NEW finding, proceed normally.

### Cross-reference

- Compare local hook rates vs remote fleet-wide rates
- Check memory feedback against consumed findings for unaddressed items
- Check remote feedback for patterns reported by multiple installs
- Verify the last 10 log entries to avoid re-doing or undoing prior work

If no actionable findings remain after dedup, classify as `no-op`.

## Phase 4: Prioritization

Rank findings by impact:

1. **Regression fixes** — always highest priority (something broke)
2. **Installs affected** — remote data shows scope. Fleet-wide > local-only
3. **Severity** — blocks work (high) > noise (medium) > cosmetic (low)
4. **Frequency** — 200 fires/day > 1 fire/week

Select the **top 1-3 highest-impact findings**. Each must have a finding_key and measurable baseline.

**If `--category` was passed**: Filter to that category only.

**If `--dry-run` was passed**: Stop here. Report:
- Verification results from Phase 2
- Full prioritized findings list with categories, baselines, and proposed changes
- Baseline snapshot summary
Do not implement or log anything.

## Phase 5: Implementation

For each selected finding, implement the change in `plugin/` source.

For each change:
1. Read the target file first — verify current state matches expectations
2. Make targeted edits — not full file rewrites
3. Syntax check: `bash -n {file}` for shell scripts
4. Record the **finding_key** and **before-value** — you will need these for logging

## Phase 6: Validation + After Measurement

### 6a. Run tests

```bash
./tests/run-tests.sh
```

If tests fail: fix the issue. If fixing requires reverting your change, revert it and note as a failed attempt in the log.

### 6b. Syntax check all changed scripts

```bash
for f in {list of changed .sh files}; do bash -n "$f"; done
```

### 6c. Capture after-snapshot

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/capture-snapshot.sh ${DAYS:-7} > /tmp/improve-after.json
```

### 6d. Compare before vs after

Read both `/tmp/improve-baseline.json` and `/tmp/improve-after.json`. For each metric relevant to your changes:

| Metric | Before | After | Verdict |
|---|---|---|---|
| {metric name} | {before value} | {after value} | IMPROVED / SAME / REGRESSED |

**Decision rules:**
- **IMPROVED**: Keep the change. Log with both before and after values.
- **SAME**: Keep the change if it's structural (new tests, better messages) where metrics won't shift immediately. Note that verification will happen in a future iteration.
- **REGRESSED**: Revert the change immediately. Log as a failed attempt with the regression data.

Note: Some changes (new hooks, test additions, prompt improvements) won't show metric movement until agents use the updated plugin. For these, log with `status: pending_validation` so the next iteration verifies.

## Phase 7: Logging

For each implemented change:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/log-improvement.sh \
  "{category}" \
  "{description with before→after numbers}" \
  "{data_sources}" \
  "{scope}" \
  "{baseline_value}" \
  "{finding_key}"
```

**Description** — Include before→after when measurable: "Raise weasel threshold from 1→3 in stop-gate — 42%→12% warn rate (208→55 warns)."

**Baseline** — Always provide the before-state metric. This is required for future verification. If no single metric applies, use the most relevant proxy (e.g., `0-tests` for test-gap fixes).

**Finding key** — The `{category}:{component}` identifier. This writes to consumed-findings.jsonl for dedup in future iterations.

For no-op iterations:
```bash
bash ${CLAUDE_SKILL_DIR}/scripts/log-improvement.sh \
  "no-op" \
  "{reason + verification summary, e.g., System at 95% health. Prior fixes: 3 VALIDATED, 0 REGRESSED}" \
  "telemetry:{count}-events" \
  "[all]" \
  "{allow-rate}%-allow-rate" \
  "no-op:system"
```

## Edge Cases

- **No metrics.db or sqlite3**: Snapshots will have null values. Proceed with events.jsonl and remote data. Before/after comparison limited to remote metrics and event counts.
- **Remote telemetry unavailable**: Local-only analysis. Snapshot captures what's available. Note the gap.
- **First iteration (no consumed-findings.jsonl)**: Skip Phase 2 verification. All findings are new. The registry will be created by Phase 7 logging.
- **All metrics healthy, no anomalies**: Successful no-op. Log it with verification summary.
- **Change reverted due to regression**: Log the attempt with REGRESSED verdict and the before→after numbers. This is valuable data — it shows what doesn't work.
- **Repeated no-ops**: System may be stable. Consider deeper analysis: long-tail issues, documentation gaps, code quality improvements that metrics don't capture.
- **Conflicting local vs remote signals**: Prefer remote (larger sample) unless local environment is clearly different (custom thresholds, specific OS).
