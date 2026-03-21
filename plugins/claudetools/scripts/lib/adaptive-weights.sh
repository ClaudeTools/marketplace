#!/bin/bash
# adaptive-weights.sh — Shared library for adaptive threshold management
# Usage: source "$(dirname "$0")/lib/adaptive-weights.sh"

# Requires ensure-db.sh to be sourced first (for METRICS_DB)

get_threshold() {
  local metric_name="$1"
  local model_family="${2:-}"

  if ! command -v sqlite3 &>/dev/null || [ ! -f "${METRICS_DB:-}" ]; then
    # Fallback defaults for critical thresholds
    case "$metric_name" in
      edit_frequency_limit) echo "3" ;;
      failure_loop_limit) echo "3" ;;
      diverse_failure_total_warn) echo "5" ;;
      churn_warning) echo "2.0" ;;
      failure_warning) echo "10" ;;
      memory_confidence_inject) echo "0.7" ;;
      memory_decay_rate) echo "0.95" ;;
      memory_decay_window_days) echo "30" ;;
      memory_prune_threshold) echo "0.1" ;;
      ts_any_limit) echo "3" ;;
      ts_as_any_limit) echo "2" ;;
      ts_ignore_limit) echo "1" ;;
      uncommitted_file_limit) echo "5" ;;
      large_change_threshold) echo "15" ;;
      ai_audit_diff_threshold) echo "30" ;;
      outcome_retention_days) echo "90" ;;
      stub_sensitivity) echo "1.0" ;;
      memory_retrieval_limit) echo "3" ;;
      memory_fts_min_rank) echo "-5" ;;
      read_warn_lines) echo "1000" ;;
      read_block_lines) echo "5000" ;;
      *) echo "3" ;; # safe default
    esac
    return
  fi

  local value
  value=$(sqlite3 "$METRICS_DB" \
    "SELECT current_value FROM threshold_overrides WHERE metric_name='$metric_name';" 2>/dev/null || true)

  if [ -z "$value" ]; then
    # Try default_value
    value=$(sqlite3 "$METRICS_DB" \
      "SELECT default_value FROM threshold_overrides WHERE metric_name='$metric_name';" 2>/dev/null || true)
  fi

  # Apply model multiplier if specified
  if [ -n "$model_family" ] && [ -n "$value" ]; then
    local multiplier
    multiplier=$(sqlite3 "$METRICS_DB" \
      "SELECT multiplier FROM model_profiles WHERE model_family='$model_family' AND (metric_name='$metric_name' OR metric_name='*') ORDER BY CASE WHEN metric_name='$metric_name' THEN 0 ELSE 1 END LIMIT 1;" 2>/dev/null || true)
    if [ -n "$multiplier" ]; then
      value=$(awk "BEGIN {printf \"%.2f\", $value * $multiplier}")
    fi
  fi

  # Clamp to bounds
  if [ -n "$value" ]; then
    local bounds
    bounds=$(sqlite3 "$METRICS_DB" \
      "SELECT min_bound, max_bound FROM threshold_overrides WHERE metric_name='$metric_name';" 2>/dev/null || true)
    if [ -n "$bounds" ]; then
      local min_b=$(echo "$bounds" | cut -d'|' -f1)
      local max_b=$(echo "$bounds" | cut -d'|' -f2)
      value=$(awk "BEGIN {v=$value; mn=$min_b; mx=$max_b; if(v<mn) v=mn; if(v>mx) v=mx; printf \"%.2f\", v}")
    fi
  fi

  echo "${value:-3}"
}

record_hook_outcome() {
  local hook_name="$1"
  local event_type="$2"
  local decision="$3"
  local tool_name="${4:-}"
  local threshold_name="${5:-}"
  local threshold_used="${6:-}"
  local model_family="${7:-}"
  local session_id="${TRAINING_SESSION_ID:-${SESSION_ID:-}}"
  if [ -z "$session_id" ]; then
    session_id=$(echo "${INPUT:-}" | jq -r '.session_id // empty' 2>/dev/null || true)
  fi
  session_id="${session_id:-unknown}"

  if ! command -v sqlite3 &>/dev/null || [ ! -f "${METRICS_DB:-}" ]; then
    return 0
  fi

  # Non-blocking background insert
  (sqlite3 "$METRICS_DB" \
    "INSERT INTO hook_outcomes (session_id, hook_name, event_type, decision, tool_name, threshold_name, threshold_used, model_family)
     VALUES ('$session_id', '$hook_name', '$event_type', '$decision', '$tool_name', '$threshold_name', '$threshold_used', '$model_family');" 2>/dev/null || true) &
}

classify_outcome() {
  local outcome_id="$1"
  local is_correct="$2"
  local classification="$3"

  sqlite3 "$METRICS_DB" \
    "UPDATE hook_outcomes SET is_correct=$is_correct, classification='$classification' WHERE id=$outcome_id;" 2>/dev/null || true
}

compute_hook_metrics() {
  local hook_name="$1"
  local since="${2:-}"

  local where_clause="WHERE hook_name='$hook_name' AND classification IS NOT NULL"
  [ -n "$since" ] && where_clause="$where_clause AND timestamp > '$since'"

  AW_TP=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes $where_clause AND classification='TP';" 2>/dev/null || echo "0")
  AW_FP=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes $where_clause AND classification='FP';" 2>/dev/null || echo "0")
  AW_TN=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes $where_clause AND classification='TN';" 2>/dev/null || echo "0")
  AW_FN=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM hook_outcomes $where_clause AND classification='FN';" 2>/dev/null || echo "0")

  local total=$((AW_TP + AW_FP + AW_TN + AW_FN))

  if [ "$total" -eq 0 ]; then
    AW_PRECISION="1.0"
    AW_RECALL="1.0"
    AW_FP_RATE="0.0"
    AW_FN_RATE="0.0"
    return
  fi

  local tp_fp=$((AW_TP + AW_FP))
  local tp_fn=$((AW_TP + AW_FN))
  local fp_tn=$((AW_FP + AW_TN))
  local fn_tn=$((AW_FN + AW_TN))

  AW_PRECISION=$(awk "BEGIN {if($tp_fp>0) printf \"%.4f\", $AW_TP/$tp_fp; else print \"1.0\"}")
  AW_RECALL=$(awk "BEGIN {if($tp_fn>0) printf \"%.4f\", $AW_TP/$tp_fn; else print \"1.0\"}")
  AW_FP_RATE=$(awk "BEGIN {if($fp_tn>0) printf \"%.4f\", $AW_FP/$fp_tn; else print \"0.0\"}")
  AW_FN_RATE=$(awk "BEGIN {if($tp_fn>0) printf \"%.4f\", $AW_FN/$tp_fn; else print \"0.0\"}")
}

adjust_threshold() {
  local metric_name="$1"
  local new_value="$2"
  local trigger="$3"
  local precision_at="${4:-}"
  local recall_at="${5:-}"
  local lr="${6:-}"
  local session_id="${7:-}"

  # Read current value and bounds
  local row
  row=$(sqlite3 "$METRICS_DB" \
    "SELECT current_value, min_bound, max_bound FROM threshold_overrides WHERE metric_name='$metric_name';" 2>/dev/null || true)
  [ -z "$row" ] && return 1

  local current=$(echo "$row" | cut -d'|' -f1)
  local min_b=$(echo "$row" | cut -d'|' -f2)
  local max_b=$(echo "$row" | cut -d'|' -f3)

  # Clamp
  new_value=$(awk "BEGIN {v=$new_value; mn=$min_b; mx=$max_b; if(v<mn) v=mn; if(v>mx) v=mx; printf \"%.4f\", v}")

  # Check if actually changed (within 0.001 tolerance)
  local changed=$(awk "BEGIN {d=$new_value-$current; if(d<0) d=-d; if(d<0.001) print 0; else print 1}")
  [ "$changed" = "0" ] && return 1

  # Update threshold
  sqlite3 "$METRICS_DB" \
    "UPDATE threshold_overrides SET current_value=$new_value, last_updated=datetime('now'), reason='$trigger' WHERE metric_name='$metric_name';" 2>/dev/null || true

  # Audit trail
  sqlite3 "$METRICS_DB" \
    "INSERT INTO threshold_history (metric_name, old_value, new_value, trigger, precision_at_change, recall_at_change, learning_rate, session_id)
     VALUES ('$metric_name', $current, $new_value, '$trigger', ${precision_at:-NULL}, ${recall_at:-NULL}, ${lr:-NULL}, '${session_id:-}');" 2>/dev/null || true

  return 0
}

reset_threshold() {
  local metric_name="$1"
  local trigger="${2:-manual-reset}"

  local default_val
  default_val=$(sqlite3 "$METRICS_DB" \
    "SELECT default_value FROM threshold_overrides WHERE metric_name='$metric_name';" 2>/dev/null || true)
  [ -z "$default_val" ] && return 1

  adjust_threshold "$metric_name" "$default_val" "$trigger"
}

get_hook_category() {
  local hook_name="$1"
  case "$hook_name" in
    block-dangerous-bash|guard-sensitive-files|ai-safety-check|detect-hardcoded-secrets)
      echo "safety" ;;
    verify-no-stubs|edit-frequency-guard|failure-pattern-detector|check-mock-in-prod|block-stub-writes)
      echo "quality" ;;
    enforce-git-commits|require-active-task|session-stop-gate|enforce-deploy-then-verify|block-unasked-restructure)
      echo "process" ;;
    inject-session-context|aggregate-session|doc-manager|doc-stale-detector|doc-index-generator)
      echo "context" ;;
    *)
      echo "general" ;;
  esac
}

get_cost_weights() {
  local category="$1"
  case "$category" in
    safety)  echo "1 10" ;;
    quality) echo "1 3" ;;
    process) echo "1 2" ;;
    context) echo "1 1" ;;
    *)       echo "1 1" ;;
  esac
}

get_target_rates() {
  local category="$1"
  case "$category" in
    safety)  echo "0.02 0.00" ;;
    quality) echo "0.05 0.01" ;;
    process) echo "0.05 0.02" ;;
    context) echo "0.10 0.05" ;;
    *)       echo "0.05 0.05" ;;
  esac
}

detect_model_family() {
  # Cache result in environment to avoid repeated JSON parsing across hook calls
  if [ -n "${_CACHED_MODEL_FAMILY:-}" ]; then
    echo "$_CACHED_MODEL_FAMILY"
    return
  fi

  local model="${CLAUDE_MODEL:-}"
  if [ -z "$model" ]; then
    model=$(echo "${INPUT:-}" | jq -r '.model // empty' 2>/dev/null || true)
  fi
  case "$model" in
    *opus*) _CACHED_MODEL_FAMILY="opus" ;;
    *sonnet*) _CACHED_MODEL_FAMILY="sonnet" ;;
    *haiku*) _CACHED_MODEL_FAMILY="haiku" ;;
    *) _CACHED_MODEL_FAMILY="unknown" ;;
  esac
  export _CACHED_MODEL_FAMILY
  echo "$_CACHED_MODEL_FAMILY"
}
