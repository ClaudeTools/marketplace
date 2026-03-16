#!/bin/bash
# tune-weights.sh — Adaptive threshold tuning via cost-sensitive bounded gradient descent
# Usage: tune-weights.sh [--session SESSION_ID] [--learning-rate LR] [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/ensure-db.sh"
source "$SCRIPT_DIR/lib/adaptive-weights.sh"

# Parse args
SESSION_ID=""
BASE_LR=0.1
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ID="$2"; shift 2 ;;
    --learning-rate) BASE_LR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

ensure_metrics_db || { echo "No metrics DB"; exit 1; }

MIN_SAMPLES=10

# LR decay based on iteration count
iteration_count=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(DISTINCT session_id) FROM threshold_history;" 2>/dev/null || echo "0")
current_lr=$(awk "BEGIN {printf \"%.6f\", $BASE_LR * (0.95 ^ $iteration_count)}")

echo "=== Adaptive Weight Tuning ==="
echo "Learning rate: $current_lr (base=$BASE_LR, iteration=$iteration_count)"
echo "Min samples: $MIN_SAMPLES"
echo ""

# Hook-to-threshold mapping
declare -A HOOK_THRESHOLD_MAP
HOOK_THRESHOLD_MAP=(
  ["edit-frequency-guard"]="edit_frequency_limit"
  ["failure-pattern-detector"]="failure_loop_limit diverse_failure_total_warn"
  ["verify-no-stubs"]="ts_any_limit ts_as_any_limit ts_ignore_limit"
  ["enforce-git-commits"]="uncommitted_file_limit"
  ["session-stop-gate"]="large_change_threshold ai_audit_diff_threshold"
  ["inject-session-context"]="churn_warning failure_warning memory_confidence_inject memory_decay_rate"
)

# Get all models that have classified data
models_with_data=$(sqlite3 "$METRICS_DB" \
  "SELECT DISTINCT model_family FROM hook_outcomes
   WHERE classification IS NOT NULL AND model_family IS NOT NULL AND model_family != '' AND model_family != 'unknown';" 2>/dev/null || true)

# Also check if there's untagged (aggregate) data
aggregate_count=$(sqlite3 "$METRICS_DB" \
  "SELECT COUNT(*) FROM hook_outcomes
   WHERE classification IS NOT NULL AND (model_family IS NULL OR model_family = '' OR model_family = 'unknown');" 2>/dev/null || echo "0")

if [ -z "$models_with_data" ] && [ "$aggregate_count" -eq 0 ]; then
  echo "No classified outcomes yet. Run training first."
  exit 0
fi

# Build list: specific models first, then aggregate if it has data
all_models="$models_with_data"
if [ "$aggregate_count" -gt 0 ]; then
  all_models=$(printf '%s\naggregate' "$all_models" | sed '/^$/d')
fi

ADJUSTMENTS=0

while IFS= read -r model; do
  [ -z "$model" ] && continue

  echo ""
  echo "=== Model: $model ==="

  # Build WHERE clause for this model
  model_where=""
  if [ "$model" = "aggregate" ]; then
    model_where="AND (model_family IS NULL OR model_family = '' OR model_family = 'unknown')"
  else
    model_where="AND model_family='$model'"
  fi

  # Get hooks with classified data for this model
  hooks_for_model=$(sqlite3 "$METRICS_DB" \
    "SELECT DISTINCT hook_name FROM hook_outcomes WHERE classification IS NOT NULL $model_where;" 2>/dev/null || true)

  [ -z "$hooks_for_model" ] && { echo "  No classified data for $model"; continue; }

  while IFS= read -r hook_name; do
    [ -z "$hook_name" ] && continue

    # Compute per-model metrics for this hook
    tp=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='TP' $model_where;" 2>/dev/null || echo "0")
    fp=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='FP' $model_where;" 2>/dev/null || echo "0")
    tn=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='TN' $model_where;" 2>/dev/null || echo "0")
    fn=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes WHERE hook_name='$hook_name' AND classification='FN' $model_where;" 2>/dev/null || echo "0")
    total=$((tp + fp + tn + fn))

    if [ "$total" -lt "$MIN_SAMPLES" ]; then
      echo "  $hook_name: $total samples (need $MIN_SAMPLES) -- skipping"
      continue
    fi

    precision="1.0"
    if [ $((tp + fp)) -gt 0 ]; then
      precision=$(awk "BEGIN {printf \"%.4f\", $tp / ($tp + $fp)}")
    fi
    recall="1.0"
    if [ $((tp + fn)) -gt 0 ]; then
      recall=$(awk "BEGIN {printf \"%.4f\", $tp / ($tp + $fn)}")
    fi
    fp_rate="0.0"
    if [ $((fp + tn)) -gt 0 ]; then
      fp_rate=$(awk "BEGIN {printf \"%.4f\", $fp / ($fp + $tn)}")
    fi
    fn_rate="0.0"
    if [ $((fn + tp)) -gt 0 ]; then
      fn_rate=$(awk "BEGIN {printf \"%.4f\", $fn / ($fn + $tp)}")
    fi

    category=$(get_hook_category "$hook_name")
    read -r target_fp target_fn <<< "$(get_target_rates "$category")"
    read -r fp_w fn_w <<< "$(get_cost_weights "$category")"

    cost=$(awk "BEGIN {printf \"%.4f\", $fp * $fp_w + $fn * $fn_w}")

    echo "  $hook_name [$category]: TP=$tp FP=$fp TN=$tn FN=$fn P=$precision R=$recall cost=$cost"

    # Safety guardrail: never auto-adjust if safety hook has FN
    if [ "$category" = "safety" ] && [ "$fn" -gt 0 ]; then
      echo "    CRITICAL: Safety hook has $fn false negatives -- manual review required"
      if [ "$DRY_RUN" = false ]; then
        sqlite3 "$METRICS_DB" \
          "INSERT OR REPLACE INTO project_memories (category, content, confidence, source)
           VALUES ('safety_alert', 'Safety hook $hook_name has $fn false negatives ($model) - review patterns immediately', 0.95, 'tune-weights');" 2>/dev/null || true
      fi
      continue
    fi

    # Find tunable thresholds for this hook
    thresholds="${HOOK_THRESHOLD_MAP[$hook_name]:-}"
    [ -z "$thresholds" ] && continue

    for threshold_name in $thresholds; do
      # Compute gradient
      fp_delta=$(awk "BEGIN {printf \"%.6f\", $fp_rate - $target_fp}")
      fn_delta=$(awk "BEGIN {printf \"%.6f\", $fn_rate - $target_fn}")
      gradient=$(awk "BEGIN {printf \"%.6f\", ($fp_delta * $fp_w - $fn_delta * $fn_w) / ($fp_w + $fn_w)}")

      if [ "$model" = "aggregate" ]; then
        # Adjust the base threshold (same as before)
        current_value=$(get_threshold "$threshold_name")
        new_value=$(awk "BEGIN {printf \"%.4f\", $current_value + $current_lr * $gradient}")

        if [ "$DRY_RUN" = true ]; then
          echo "    DRY RUN: $threshold_name: $current_value -> $new_value (gradient=$gradient)"
        else
          if adjust_threshold "$threshold_name" "$new_value" "auto-tune" "$precision" "$recall" "$current_lr" "$SESSION_ID"; then
            echo "    ADJUSTED: $threshold_name: $current_value -> $new_value"
            ADJUSTMENTS=$((ADJUSTMENTS + 1))
          else
            echo "    $threshold_name: $current_value (no change needed)"
          fi
        fi
      else
        # Per-model: adjust the model_profiles multiplier
        base_value=$(sqlite3 "$METRICS_DB" \
          "SELECT current_value FROM threshold_overrides WHERE metric_name='$threshold_name';" 2>/dev/null || echo "3")
        [ -z "$base_value" ] && base_value="3"

        # new_multiplier = (base + adjustment) / base
        adjustment=$(awk "BEGIN {printf \"%.4f\", $current_lr * $gradient}")
        new_multiplier=$(awk "BEGIN {printf \"%.4f\", ($base_value + $adjustment) / $base_value}")

        # Clamp multiplier to [0.5, 2.0]
        new_multiplier=$(awk "BEGIN {v=$new_multiplier; if(v<0.5) v=0.5; if(v>2.0) v=2.0; printf \"%.4f\", v}")

        old_multiplier=$(sqlite3 "$METRICS_DB" \
          "SELECT multiplier FROM model_profiles WHERE model_family='$model' AND metric_name='$threshold_name';" 2>/dev/null || true)
        if [ -z "$old_multiplier" ]; then
          old_multiplier=$(sqlite3 "$METRICS_DB" \
            "SELECT multiplier FROM model_profiles WHERE model_family='$model' AND metric_name='*';" 2>/dev/null || echo "1.0")
        fi

        echo "    $threshold_name [$model]: multiplier $old_multiplier -> $new_multiplier (gradient=$gradient)"

        if [ "$DRY_RUN" = false ]; then
          sqlite3 "$METRICS_DB" \
            "INSERT INTO model_profiles (model_family, metric_name, multiplier, last_updated, reason)
             VALUES ('$model', '$threshold_name', $new_multiplier, datetime('now'), 'auto-tune gradient=$gradient')
             ON CONFLICT(model_family, metric_name) DO UPDATE SET
               multiplier=$new_multiplier,
               last_updated=datetime('now'),
               reason='auto-tune gradient=$gradient (was ' || multiplier || ')';" 2>/dev/null || true
          ADJUSTMENTS=$((ADJUSTMENTS + 1))
        fi
      fi
    done
  done <<< "$hooks_for_model"
done <<< "$all_models"

# Update project memories from chronic patterns
if [ "$DRY_RUN" = false ]; then
  # Chronic failures: same hook failed 3+ times
  chronic=$(sqlite3 "$METRICS_DB" \
    "SELECT hook_name, COUNT(*) as cnt FROM hook_outcomes
     WHERE classification='FN' GROUP BY hook_name HAVING cnt >= 3;" 2>/dev/null || true)

  if [ -n "$chronic" ]; then
    echo ""
    echo "  Chronic failure patterns:"
    echo "$chronic" | while IFS='|' read -r hname cnt; do
      echo "    $hname: $cnt false negatives"
      existing=$(sqlite3 "$METRICS_DB" \
        "SELECT id FROM project_memories WHERE category='training_failure' AND content LIKE '%$hname%' LIMIT 1;" 2>/dev/null || true)
      if [ -n "$existing" ]; then
        sqlite3 "$METRICS_DB" \
          "UPDATE project_memories SET times_reinforced=times_reinforced+1, confidence=MIN(confidence+0.05,1.0), last_seen=datetime('now') WHERE id=$existing;" 2>/dev/null || true
      else
        sqlite3 "$METRICS_DB" \
          "INSERT INTO project_memories (category, content, confidence, project_type, source) VALUES ('training_failure', '$hname has chronic false negatives - review detection patterns', 0.6, 'training', 'tune-weights');" 2>/dev/null || true
      fi
    done
  fi
fi

echo ""
echo "Tuning complete: $ADJUSTMENTS adjustment(s) made"
