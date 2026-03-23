#!/bin/bash
# adaptive-weights.sh — Shared library for hook thresholds and outcome recording
# Usage: source "$(dirname "$0")/lib/adaptive-weights.sh"

get_threshold() {
  local metric_name="$1"
  # All thresholds are hardcoded — DB-based adaptive tuning was removed
  # because the SQLite lookup was unreliable on installed plugins (see 701b12f).
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
    read_warn_lines) echo "2000" ;;
    read_block_lines) echo "10000" ;;
    *) echo "3" ;; # safe default
  esac
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
    AW_PRECISION="1.0"; AW_RECALL="1.0"; AW_FP_RATE="0.0"; AW_FN_RATE="0.0"
    return
  fi
  local tp_fp=$((AW_TP + AW_FP))
  local tp_fn=$((AW_TP + AW_FN))
  local fp_tn=$((AW_FP + AW_TN))
  AW_PRECISION=$(awk "BEGIN {if($tp_fp>0) printf \"%.4f\", $AW_TP/$tp_fp; else print \"1.0\"}")
  AW_RECALL=$(awk "BEGIN {if($tp_fn>0) printf \"%.4f\", $AW_TP/$tp_fn; else print \"1.0\"}")
  AW_FP_RATE=$(awk "BEGIN {if($fp_tn>0) printf \"%.4f\", $AW_FP/$fp_tn; else print \"0.0\"}")
  AW_FN_RATE=$(awk "BEGIN {if($tp_fn>0) printf \"%.4f\", $AW_FN/$tp_fn; else print \"0.0\"}")
}

get_hook_category() {
  local hook_name="$1"
  case "$hook_name" in
    block-dangerous-bash|guard-sensitive-files|ai-safety-check|detect-hardcoded-secrets) echo "safety" ;;
    verify-no-stubs|edit-frequency-guard|failure-pattern-detector|check-mock-in-prod|block-stub-writes) echo "quality" ;;
    enforce-git-commits|require-active-task|session-stop-gate|enforce-deploy-then-verify|block-unasked-restructure) echo "process" ;;
    inject-session-context|aggregate-session|doc-manager|doc-stale-detector|doc-index-generator) echo "context" ;;
    *) echo "general" ;;
  esac
}

detect_model_family() {
  if [ -n "${_CACHED_MODEL_FAMILY:-}" ]; then
    echo "$_CACHED_MODEL_FAMILY"; return
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
