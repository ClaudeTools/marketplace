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

    # stub_sensitivity — multiplier for stub-detection scoring (1.0 = baseline)
    # Range: 0.1–2.0 | Higher = more aggressive stub flagging
    stub_sensitivity) echo "1.0" ;;

    # memory_retrieval_limit — max memory fragments surfaced per hook invocation
    # Range: 1–20 | Higher = richer context, higher token cost
    memory_retrieval_limit) echo "3" ;;

    # memory_fts_min_rank — minimum FTS5 rank score to include a memory result
    # Range: -100–0 | Less negative = stricter relevance filter
    memory_fts_min_rank) echo "-5" ;;

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
    guard-sensitive-files|ai-safety|dangerous-bash) echo "safety" ;;
    edit-frequency-guard|failure-pattern-detector|stubs|task-quality) echo "quality" ;;
    enforce-git-commits|session-stop-dispatcher|enforce-task-quality) echo "process" ;;
    inject-session-context|aggregate-session|doc-manager|doc-stale-detector) echo "context" ;;
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
