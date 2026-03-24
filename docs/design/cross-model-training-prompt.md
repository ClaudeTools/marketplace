---
title: "Implementation Prompt - Cross-Model Training and Per-Model Weights"
created: "2026-03-16"
modified: "2026-03-16"
version: "1.0.0"
status: "active"
category: "plan"
tags: ["training", "headless", "model-weights", "haiku", "sonnet", "opus"]
author: "claude"
---

# Implementation Prompt: Cross-Model Headless Training with Per-Model Adaptive Weights

Read this entire prompt before starting. This builds on the headless training prompt (`.docs/headless-training-prompt.md`). If you haven't implemented that yet, do it first - this prompt depends on `headless-runner.sh` and the `"evaluation"` field in scenario JSONs.

## Overview

Run all 11 headless scenarios across haiku, sonnet, and opus. Record per-model hook outcomes. Tune thresholds per model. When a user runs the plugin in a live session, hooks detect which model is active and apply that model's specific thresholds.

The hypothesis: haiku needs tighter guardrails (lower thresholds) because it makes more mistakes. Opus needs looser guardrails (higher thresholds) because it's more capable. The training data will confirm or disprove this and set exact multipliers per hook per model.

## Current State (Gaps to Fix)

The infrastructure is 80% there but disconnected:

### What exists:
- `model_profiles` table with per-model multipliers (opus=1.0, sonnet=1.0, haiku=0.85)
- `get_threshold(metric_name, model_family)` accepts a model parameter and applies the multiplier
- `detect_model_family()` reads `CLAUDE_MODEL` env var or `INPUT.model` JSON field
- `hook_outcomes` table has a `model_family` column
- `record_hook_outcome()` has a model_family parameter (7th arg)

### What's broken:
1. **No hook passes model to `get_threshold()`** - Every call is `get_threshold "metric_name"` with no second arg. The model multiplier never applies.
2. **No hook passes model to `record_hook_outcome()`** - The 7th arg (model_family) is never provided. All outcomes record with NULL model.
3. **`tune-weights.sh` doesn't partition by model** - It computes aggregate P/R across all models and adjusts a single `current_value`. There are no per-model threshold overrides.
4. **`model_profiles` only has wildcard multipliers** - `('haiku', '*', 0.85)` applies 0.85 to all metrics. There are no per-hook per-model multipliers learned from training data.
5. **`headless-runner.sh` doesn't export `CLAUDE_MODEL`** - So hooks during headless training can't detect which model is running.

## What to Build

### Fix 1: Make all hooks model-aware

Every hook that calls `get_threshold()` or `record_hook_outcome()` needs to detect the model and pass it through.

Add this pattern to the top of every hook that uses adaptive weights (after sourcing the libs):

```bash
MODEL_FAMILY=$(detect_model_family)
```

Then update every `get_threshold` call to pass it:

```bash
# BEFORE
EDIT_THRESHOLD=$(get_threshold "edit_frequency_limit")

# AFTER
EDIT_THRESHOLD=$(get_threshold "edit_frequency_limit" "$MODEL_FAMILY")
```

And every `record_hook_outcome` call:

```bash
# BEFORE
record_hook_outcome "edit-frequency-guard" "PostToolUse" "warn" "Edit" "edit_frequency_limit" "$EDIT_THRESHOLD"

# AFTER
record_hook_outcome "edit-frequency-guard" "PostToolUse" "warn" "Edit" "edit_frequency_limit" "$EDIT_THRESHOLD" "$MODEL_FAMILY"
```

**Files to update** (every hook that uses `get_threshold` or `record_hook_outcome`):

- `scripts/edit-frequency-guard.sh`
- `scripts/failure-pattern-detector.sh`
- `scripts/verify-no-stubs.sh`
- `scripts/block-dangerous-bash.sh`
- `scripts/auto-approve-safe.sh`
- `scripts/enforce-git-commits.sh`
- `scripts/block-stub-writes.sh`
- `scripts/require-active-task.sh`
- `scripts/check-mock-in-prod.sh`
- `scripts/enforce-deploy-then-verify.sh`
- `scripts/guard-sensitive-files.sh`
- `scripts/session-stop-gate.sh`
- `scripts/enforce-codebase-pilot.sh`
- `scripts/doc-manager.sh` (if it uses adaptive weights)

For each file:
1. Add `MODEL_FAMILY=$(detect_model_family)` near the top (after sourcing libs, after reading INPUT)
2. Add `"$MODEL_FAMILY"` as the second arg to every `get_threshold` call
3. Add `"$MODEL_FAMILY"` as the last arg to every `record_hook_outcome` call

### Fix 2: Export model in headless-runner.sh

In `headless-runner.sh`, the `claude -p --model haiku` execution sets the model but hooks inside that session need to see it. Claude Code should set `CLAUDE_MODEL` internally, but to be safe, also pass it in the prompt and as an environment hint.

Update `headless-runner.sh` to export the model before execution:

```bash
# Add before the claude -p call
export CLAUDE_MODEL="claude-${MODEL}-4-6"
# For haiku specifically the version string differs:
case "$MODEL" in
  haiku) export CLAUDE_MODEL="claude-haiku-4-5" ;;
  sonnet) export CLAUDE_MODEL="claude-sonnet-4-6" ;;
  opus) export CLAUDE_MODEL="claude-opus-4-6" ;;
  *) export CLAUDE_MODEL="$MODEL" ;;
esac
```

Also add the model to the JSON result output (it's already there from the headless prompt).

### Fix 3: Per-model threshold storage

The current `threshold_overrides` table stores one `current_value` per metric. For per-model weights, we need either:

**Option A: Expand model_profiles (recommended)**

The `model_profiles` table already supports per-metric per-model multipliers. Instead of adding columns to threshold_overrides, store learned multipliers in model_profiles:

```sql
-- Currently:
-- ('haiku', '*', 0.85) -- one wildcard for all metrics

-- After training, per-hook multipliers:
-- ('haiku', 'edit_frequency_limit', 0.70)    -- haiku needs tighter edit guard
-- ('haiku', 'failure_loop_limit', 0.65)      -- haiku fails more, catch earlier
-- ('haiku', 'ts_any_limit', 0.80)            -- haiku uses more any types
-- ('haiku', '*', 0.85)                       -- fallback for untuned metrics
-- ('sonnet', 'edit_frequency_limit', 1.05)   -- sonnet slightly looser
-- ('sonnet', '*', 1.0)                       -- fallback
-- ('opus', '*', 1.0)                         -- opus is baseline
```

The `get_threshold` function ALREADY handles this correctly - it queries:
```sql
SELECT multiplier FROM model_profiles
WHERE model_family='$model_family'
AND (metric_name='$metric_name' OR metric_name='*')
ORDER BY CASE WHEN metric_name='$metric_name' THEN 0 ELSE 1 END
LIMIT 1;
```

This returns the specific metric multiplier if it exists, falling back to the wildcard. No schema changes needed.

### Fix 4: Update tune-weights.sh to be model-aware

This is the big change. `tune-weights.sh` currently computes aggregate metrics across all models. It needs to partition by model and write per-model multipliers.

Replace the main tuning loop with model-partitioned logic:

```bash
# Get all models that have data
models_with_data=$(sqlite3 "$METRICS_DB" \
  "SELECT DISTINCT model_family FROM hook_outcomes
   WHERE classification IS NOT NULL AND model_family IS NOT NULL AND model_family != 'unknown';" 2>/dev/null || true)

if [ -z "$models_with_data" ]; then
  echo "No model-tagged classified outcomes. Falling back to aggregate tuning."
  models_with_data="aggregate"
fi

while IFS= read -r model; do
  [ -z "$model" ] && continue

  echo ""
  echo "=== Model: $model ==="

  # Build WHERE clause for this model
  local model_where=""
  if [ "$model" != "aggregate" ]; then
    model_where="AND model_family='$model'"
  fi

  while IFS= read -r hook_name; do
    [ -z "$hook_name" ] && continue

    # Compute per-model metrics for this hook
    local tp fp tn fn
    tp=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='TP' $model_where;" 2>/dev/null || echo "0")
    fp=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='FP' $model_where;" 2>/dev/null || echo "0")
    tn=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='TN' $model_where;" 2>/dev/null || echo "0")
    fn=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='FN' $model_where;" 2>/dev/null || echo "0")
    local total=$((tp + fp + tn + fn))

    if [ "$total" -lt "$MIN_SAMPLES" ]; then
      echo "  $hook_name: $total samples (need $MIN_SAMPLES) -- skipping"
      continue
    fi

    local precision recall
    if [ $((tp + fp)) -gt 0 ]; then
      precision=$(awk "BEGIN {printf \"%.4f\", $tp / ($tp + $fp)}")
    else
      precision="1.0"
    fi
    if [ $((tp + fn)) -gt 0 ]; then
      recall=$(awk "BEGIN {printf \"%.4f\", $tp / ($tp + $fn)}")
    else
      recall="1.0"
    fi

    echo "  $hook_name: TP=$tp FP=$fp TN=$tn FN=$fn P=$precision R=$recall"

    # Determine threshold adjustments
    local thresholds="${HOOK_THRESHOLD_MAP[$hook_name]:-}"
    [ -z "$thresholds" ] && continue

    for threshold_name in $thresholds; do
      local current
      current=$(sqlite3 "$METRICS_DB" "SELECT current_value FROM threshold_overrides WHERE metric_name='$threshold_name';" 2>/dev/null || echo "3")

      # Calculate adjustment direction
      # High FP rate -> threshold too tight -> increase (relax)
      # High FN rate -> threshold too loose -> decrease (tighten)
      local adjustment=0
      local trigger=""

      local category=$(get_hook_category "$hook_name")
      read -r fp_w fn_w <<< "$(get_cost_weights "$category")"

      if [ "$fp" -gt 0 ] && [ "$(awk "BEGIN {print ($fp/($fp+$tn+0.001) > 0.05)}")" = "1" ]; then
        adjustment=$(awk "BEGIN {printf \"%.4f\", $current_lr * $fp_w * ($fp / $total)}")
        trigger="FP_rate=$(awk "BEGIN {printf \"%.2f\", $fp/($fp+$tn+0.001)}")"
      fi
      if [ "$fn" -gt 0 ] && [ "$(awk "BEGIN {print ($fn/($fn+$tp+0.001) > 0.02)}")" = "1" ]; then
        adjustment=$(awk "BEGIN {printf \"%.4f\", -1 * $current_lr * $fn_w * ($fn / $total)}")
        trigger="FN_rate=$(awk "BEGIN {printf \"%.2f\", $fn/($fn+$tp+0.001)}")"
      fi

      if [ "$adjustment" != "0" ] && [ -n "$trigger" ]; then
        if [ "$model" = "aggregate" ]; then
          # Adjust the base threshold
          local new_value
          new_value=$(awk "BEGIN {printf \"%.2f\", $current + $adjustment}")
          echo "    $threshold_name: $current -> $new_value ($trigger)"

          if ! $DRY_RUN; then
            adjust_threshold "$threshold_name" "$new_value" "$trigger" "$precision" "$recall" "$current_lr" "$SESSION_ID"
          fi
        else
          # Adjust the model multiplier for this specific metric
          local base_value
          base_value=$(sqlite3 "$METRICS_DB" "SELECT current_value FROM threshold_overrides WHERE metric_name='$threshold_name';" 2>/dev/null || echo "3")

          # Desired threshold = base_value * multiplier
          # If we want to adjust by $adjustment, new_multiplier = (base + adjustment) / base
          local new_multiplier
          new_multiplier=$(awk "BEGIN {printf \"%.4f\", ($base_value + $adjustment) / $base_value}")

          # Clamp multiplier to reasonable range [0.5, 2.0]
          new_multiplier=$(awk "BEGIN {v=$new_multiplier; if(v<0.5) v=0.5; if(v>2.0) v=2.0; printf \"%.4f\", v}")

          local old_multiplier
          old_multiplier=$(sqlite3 "$METRICS_DB" \
            "SELECT multiplier FROM model_profiles WHERE model_family='$model' AND metric_name='$threshold_name';" 2>/dev/null || echo "")

          if [ -z "$old_multiplier" ]; then
            # Check wildcard
            old_multiplier=$(sqlite3 "$METRICS_DB" \
              "SELECT multiplier FROM model_profiles WHERE model_family='$model' AND metric_name='*';" 2>/dev/null || echo "1.0")
          fi

          echo "    $threshold_name [$model]: multiplier $old_multiplier -> $new_multiplier ($trigger)"

          if ! $DRY_RUN; then
            sqlite3 "$METRICS_DB" \
              "INSERT INTO model_profiles (model_family, metric_name, multiplier, last_updated, reason)
               VALUES ('$model', '$threshold_name', $new_multiplier, datetime('now'), '$trigger')
               ON CONFLICT(model_family, metric_name) DO UPDATE SET
                 multiplier=$new_multiplier,
                 last_updated=datetime('now'),
                 reason='$trigger (was ' || multiplier || ')';" 2>/dev/null || true
            ADJUSTMENTS=$((ADJUSTMENTS + 1))
          fi
        fi
      fi
    done
  done <<< "$hooks_with_data_for_model"

done <<< "$models_with_data"
```

**Important**: You need to get hooks_with_data scoped per model. Before the inner loop add:

```bash
  local hooks_with_data_for_model
  if [ "$model" = "aggregate" ]; then
    hooks_with_data_for_model=$(sqlite3 "$METRICS_DB" \
      "SELECT DISTINCT hook_name FROM hook_outcomes WHERE classification IS NOT NULL;" 2>/dev/null || true)
  else
    hooks_with_data_for_model=$(sqlite3 "$METRICS_DB" \
      "SELECT DISTINCT hook_name FROM hook_outcomes WHERE classification IS NOT NULL AND model_family='$model';" 2>/dev/null || true)
  fi
```

### Fix 5: Create the cross-model training runner

New file: `tests/training/train-cross-model.sh`

This is a wrapper that runs the 11 headless scenarios across all 3 models and generates a comparison report.

```bash
#!/usr/bin/env bash
# train-cross-model.sh - Run headless scenarios across haiku, sonnet, opus
# Usage: train-cross-model.sh [--budget-per-scenario USD] [--max-turns N] [--scenarios-dir DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
CROSS_MODEL_LOG="$RESULTS_DIR/cross-model-log.jsonl"

mkdir -p "$RESULTS_DIR"

BUDGET="0.50"
MAX_TURNS=15
SCENARIOS_DIR="$SCRIPT_DIR/scenarios/code"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) BUDGET="$2"; shift 2 ;;
    --max-turns) MAX_TURNS="$2"; shift 2 ;;
    --scenarios-dir) SCENARIOS_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

MODELS=("haiku" "sonnet" "opus")

echo "============================================="
echo "  Cross-Model Training Run"
echo "  Models: ${MODELS[*]}"
echo "  Budget per scenario: \$$BUDGET"
echo "  Max turns: $MAX_TURNS"
echo "============================================="
echo ""

TOTAL_COST=0
GRAND_TOTAL=0
GRAND_PASS=0

for MODEL in "${MODELS[@]}"; do
  echo ""
  echo "============================================="
  echo "  Model: $MODEL"
  echo "============================================="

  MODEL_PASS=0
  MODEL_FAIL=0
  MODEL_COST=0
  MODEL_TIME=0

  for scenario_file in "$SCENARIOS_DIR"/*.json; do
    [ ! -f "$scenario_file" ] && continue
    eval_type=$(jq -r '.evaluation // "deterministic"' "$scenario_file")
    [ "$eval_type" != "headless" ] && continue

    name=$(jq -r '.name' "$scenario_file")
    scaffold=$(jq -r '.scaffold // "general-project"' "$scenario_file")

    # Create workspace
    workspace=$(mktemp -d)
    scaffold_dir="$TESTS_DIR/scaffolds/$scaffold"
    [ -d "$scaffold_dir" ] && cp -r "$scaffold_dir"/. "$workspace"/ 2>/dev/null || true
    cd "$workspace" && git init -q 2>/dev/null && git config user.email "t@t.com" && git config user.name "T" 2>/dev/null || true

    # Run setup
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      (cd "$workspace" && eval "$cmd") >/dev/null 2>&1 || true
    done < <(jq -r '.setup_commands // [] | .[]' "$scenario_file" 2>/dev/null)

    echo -n "  $name: "

    result=$(bash "$SCRIPT_DIR/headless-runner.sh" \
      "$scenario_file" "$workspace" \
      --model "$MODEL" \
      --max-turns "$MAX_TURNS" \
      --budget "$BUDGET" \
      2>/dev/null) || result='{"success":false,"score":"0%","cost_usd":0,"duration_seconds":0}'

    success=$(echo "$result" | jq -r '.success // false')
    score=$(echo "$result" | jq -r '.score // "0%"')
    cost=$(echo "$result" | jq -r '.cost_usd // 0')
    duration=$(echo "$result" | jq -r '.duration_seconds // 0')

    GRAND_TOTAL=$((GRAND_TOTAL + 1))

    if [ "$success" = "true" ]; then
      MODEL_PASS=$((MODEL_PASS + 1))
      GRAND_PASS=$((GRAND_PASS + 1))
      echo "PASS ($score, \$$cost, ${duration}s)"
    else
      MODEL_FAIL=$((MODEL_FAIL + 1))
      echo "FAIL ($score, \$$cost, ${duration}s)"
    fi

    MODEL_COST=$(awk "BEGIN {printf \"%.4f\", $MODEL_COST + $cost}")
    MODEL_TIME=$((MODEL_TIME + duration))

    # Log result
    echo "$result" >> "$CROSS_MODEL_LOG"

    rm -rf "$workspace" 2>/dev/null || true
  done

  local_total=$((MODEL_PASS + MODEL_FAIL))
  echo ""
  echo "  $MODEL summary: $MODEL_PASS/$local_total passed, \$$MODEL_COST total, ${MODEL_TIME}s"
  TOTAL_COST=$(awk "BEGIN {printf \"%.4f\", $TOTAL_COST + $MODEL_COST}")
done

echo ""
echo "============================================="
echo "  CROSS-MODEL SUMMARY"
echo "============================================="
echo "  Total scenarios: $GRAND_TOTAL ($((GRAND_TOTAL / 3)) per model x 3 models)"
echo "  Total passed: $GRAND_PASS"
echo "  Total cost: \$$TOTAL_COST"
echo ""

# Generate per-model comparison table
echo "  Model     | Pass Rate | Avg Cost | Avg Time"
echo "  ----------|-----------|----------|----------"

for MODEL in "${MODELS[@]}"; do
  m_total=$(jq -r "select(.model==\"$MODEL\") | .name" "$CROSS_MODEL_LOG" 2>/dev/null | wc -l | tr -d ' ')
  m_pass=$(jq -r "select(.model==\"$MODEL\" and .success==true) | .name" "$CROSS_MODEL_LOG" 2>/dev/null | wc -l | tr -d ' ')
  m_cost=$(jq -r "select(.model==\"$MODEL\") | .cost_usd" "$CROSS_MODEL_LOG" 2>/dev/null | awk '{s+=$1}END{printf "%.4f", s}')
  m_avg_cost=$(jq -r "select(.model==\"$MODEL\") | .cost_usd" "$CROSS_MODEL_LOG" 2>/dev/null | awk '{s+=$1; n++}END{if(n>0) printf "%.4f", s/n; else print "0"}')
  m_avg_time=$(jq -r "select(.model==\"$MODEL\") | .duration_seconds" "$CROSS_MODEL_LOG" 2>/dev/null | awk '{s+=$1; n++}END{if(n>0) printf "%.0f", s/n; else print "0"}')
  m_rate="0%"
  [ "$m_total" -gt 0 ] && m_rate=$(awk "BEGIN {printf \"%.0f%%\", $m_pass/$m_total*100}")

  printf "  %-10s| %-10s| \$%-7s | %ss\n" "$MODEL" "$m_rate" "$m_avg_cost" "$m_avg_time"
done

echo ""

# Now run tune-weights to compute per-model adjustments
echo "=== Running per-model threshold tuning ==="
bash "$PLUGIN_ROOT/scripts/tune-weights.sh" --session "cross-model-$(date +%s)" 2>&1

echo ""
echo "=== Per-model multipliers after tuning ==="
if command -v sqlite3 &>/dev/null; then
  sqlite3 "$PLUGIN_ROOT/data/metrics.db" \
    "SELECT model_family, metric_name, multiplier, reason FROM model_profiles ORDER BY model_family, metric_name;" 2>/dev/null | \
    column -t -s'|' 2>/dev/null || true
fi

echo ""
echo "Cross-model training complete. Results in: $CROSS_MODEL_LOG"
```

### Fix 6: Update /train skill with cross-model command

Add to `skills/train/SKILL.md`:

```markdown
### /train cross-model
Run all 11 headless scenarios across haiku, sonnet, and opus.
Generates per-model comparison data and tunes per-model weight multipliers.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/tests/training/train-cross-model.sh
```
Estimated cost: ~$8-30 depending on scenario complexity.
After completion, model_profiles table will have per-hook per-model multipliers
that are automatically applied when users run the plugin with different models.

### /train cross-model-dry-run
Preview what threshold adjustments would be made without applying them.
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/tune-weights.sh --dry-run
```
```

---

## How It All Connects at Runtime

When a user installs the plugin and starts a Claude Code session:

```
User starts session with sonnet
  |
  v
Hook fires (e.g. edit-frequency-guard)
  |
  v
MODEL_FAMILY=$(detect_model_family)  --> "sonnet"
  |
  v
EDIT_THRESHOLD=$(get_threshold "edit_frequency_limit" "sonnet")
  |
  v
get_threshold reads threshold_overrides:
  current_value = 3.0  (base threshold)
  |
  v
get_threshold reads model_profiles:
  SELECT multiplier FROM model_profiles
  WHERE model_family='sonnet' AND metric_name='edit_frequency_limit'
  --> 1.05  (learned: sonnet needs slightly looser edit guard)
  |
  v
  3.0 * 1.05 = 3.15 (effective threshold for sonnet)
  |
  v
Clamp to bounds [1.5, 6.0] --> 3.15
  |
  v
Hook uses 3.15 as its threshold instead of 3.0
```

If the same user switches to haiku:
```
  current_value = 3.0
  multiplier for haiku + edit_frequency_limit = 0.70
  3.0 * 0.70 = 2.10 (tighter for haiku)
```

---

## Execution Order

1. Fix all hooks to pass `MODEL_FAMILY` to `get_threshold` and `record_hook_outcome` (Fix 1)
2. Update `headless-runner.sh` to export `CLAUDE_MODEL` (Fix 2)
3. Update `tune-weights.sh` with model-partitioned tuning logic (Fix 4)
4. Create `tests/training/train-cross-model.sh` (Fix 5)
5. Update `/train` skill (Fix 6)
6. Run a single headless scenario with haiku to verify model detection:
   ```bash
   TRAINING_MODEL=haiku bash tests/training/headless-runner.sh \
     tests/training/scenarios/code/add-authentication.json \
     /tmp/test-workspace --model haiku
   ```
   Then check: `sqlite3 data/metrics.db "SELECT model_family, COUNT(*) FROM hook_outcomes GROUP BY model_family;"`
   Should show entries tagged with "haiku".
7. Run full cross-model training:
   ```bash
   bash tests/training/train-cross-model.sh
   ```
8. Verify model_profiles has per-hook multipliers:
   ```bash
   sqlite3 data/metrics.db "SELECT * FROM model_profiles ORDER BY model_family, metric_name;"
   ```
9. Commit and push

---

## Expected Results

Based on general model capability differences, training will likely show:

| Hook | Haiku Multiplier | Sonnet Multiplier | Opus Multiplier |
|---|---|---|---|
| edit_frequency_limit | 0.65-0.80 (tighter) | 0.95-1.05 (similar) | 1.0-1.15 (looser) |
| failure_loop_limit | 0.60-0.75 (catch earlier) | 0.90-1.00 | 1.0-1.10 |
| ts_any_limit | 0.70-0.85 (haiku uses more any) | 0.95-1.05 | 1.0 |
| stub_sensitivity | 0.70-0.85 (more stubs) | 0.95-1.05 | 1.0-1.10 |

These are hypotheses. The training data will set exact values. The point is that the same plugin adapts its behaviour based on which model the user is running - tighter guardrails for less capable models, looser for more capable ones.

---

## Cost Estimate for Full Cross-Model Run

| Model | Scenarios | Est. per Scenario | Est. Total |
|---|---|---|---|
| Haiku | 11 | $0.02-0.10 | $0.22-1.10 |
| Sonnet | 11 | $0.10-0.50 | $1.10-5.50 |
| Opus | 11 | $0.50-2.00 | $5.50-22.00 |
| **Total** | **33** | | **$6.82-28.60** |

Budget flags cap the maximum. Realistic total with the $0.50 per-scenario cap: ~$16.50 worst case.
