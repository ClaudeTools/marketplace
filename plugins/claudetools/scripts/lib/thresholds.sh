#!/bin/bash
# thresholds.sh — Static threshold configuration for hook behavior
# Usage: source "$(dirname "$0")/lib/thresholds.sh"

get_threshold() {
  local metric_name="$1"
  case "$metric_name" in
    # edit_frequency_limit — max consecutive edits to the same file before warning
    # Range: 1–10 | Higher = more permissive, lower = stricter churn detection
    edit_frequency_limit) echo "3" ;;

    # failure_loop_limit — max repeated tool failures before flagging a loop
    # Range: 1–10 | Higher = more patient, lower = catches runaway retries sooner
    failure_loop_limit) echo "3" ;;

    # diverse_failure_total_warn — total distinct failure types before a session-level warning
    # Range: 1–20 | Higher = suppresses warnings longer, lower = more sensitive
    diverse_failure_total_warn) echo "5" ;;

    # churn_warning — churn ratio (edit/create ratio) that triggers a quality warning
    # Range: 0.1–5.0 | Higher = permits more rewriting before warning
    churn_warning) echo "2.0" ;;

    # failure_warning — cumulative failure count before raising a process alert
    # Range: 5–50 | Higher = more tolerant of transient errors
    failure_warning) echo "10" ;;

    # memory_confidence_inject — minimum confidence score to inject a memory fragment
    # Range: 0.0–1.0 | Higher = only high-confidence memories injected
    memory_confidence_inject) echo "0.7" ;;

    # memory_decay_rate — multiplier applied to memory confidence per decay window
    # Range: 0.1–1.0 | Lower = memories age out faster
    memory_decay_rate) echo "0.95" ;;

    # memory_decay_window_days — how many days constitute one decay cycle
    # Range: 1–365 | Shorter = faster decay
    memory_decay_window_days) echo "30" ;;

    # memory_prune_threshold — confidence floor below which memories are pruned
    # Range: 0.0–1.0 | Higher = prunes more aggressively
    memory_prune_threshold) echo "0.1" ;;

    # ts_any_limit — max `any` type usages allowed before flagging
    # Range: 0–20 | Lower = stricter TypeScript quality enforcement
    ts_any_limit) echo "3" ;;

    # ts_as_any_limit — max `as any` casts allowed before flagging
    # Range: 0–10 | Lower = fewer escape hatches permitted
    ts_as_any_limit) echo "2" ;;

    # ts_ignore_limit — max @ts-ignore directives allowed before flagging
    # Range: 0–10 | Lower = stricter suppression discipline
    ts_ignore_limit) echo "1" ;;

    # uncommitted_file_limit — max uncommitted changed files before a commit reminder
    # Range: 1–50 | Higher = more work allowed before prompting a commit
    uncommitted_file_limit) echo "5" ;;

    # large_change_threshold — file count above which a change is considered "large"
    # Range: 5–100 | Higher = larger PRs permitted without special handling
    large_change_threshold) echo "15" ;;

    # ai_audit_diff_threshold — diff line count above which an AI audit is triggered
    # Range: 10–200 | Higher = audits only very large diffs
    ai_audit_diff_threshold) echo "30" ;;

    # outcome_retention_days — how long hook outcome records are kept in the DB
    # Range: 7–365 | Higher = more history for trend analysis
    outcome_retention_days) echo "90" ;;

    # read_warn_lines — line count above which a file read triggers a warning
    # Range: 100–5000 | Higher = more lenient about large file reads
    read_warn_lines) echo "2000" ;;

    # read_block_lines — line count above which a file read is blocked entirely
    # Range: 1000–50000 | Higher = permits reading very large files
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
