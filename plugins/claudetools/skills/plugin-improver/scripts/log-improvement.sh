#!/usr/bin/env bash
# log-improvement.sh — Append to loop-improvements.log AND consumed-findings.jsonl
# Usage: log-improvement.sh <category> <description> <data_sources> <scope> [baseline] [finding_key]
#
# Human log format: [ISO-timestamp] [category] [description] [data_sources] [scope] [baseline:metric]
# Machine registry: JSONL with finding_key, status tracking, before/after for dedup and verification

set -euo pipefail

_plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)}"

# Versioned install path — use parent directory for stable data dir
if [[ "$_plugin_root" =~ /plugins/cache/.*/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  _plugin_root="$(dirname "$_plugin_root")"
fi

LOG_FILE="${_plugin_root}/logs/loop-improvements.log"
CONSUMED_FILE="${_plugin_root}/logs/consumed-findings.jsonl"

# ── Validate arguments ───────────────────────────────────────────────
if [ $# -lt 4 ]; then
  echo "Usage: log-improvement.sh <category> <description> <data_sources> <scope> [baseline] [finding_key]" >&2
  echo "  category:     one of the canonical improvement categories" >&2
  echo "  description:  what was changed and why (1-2 sentences)" >&2
  echo "  data_sources: what triggered the change (e.g., telemetry:350-events)" >&2
  echo "  scope:        [all] or project list (e.g., [emailer,aibooks])" >&2
  echo "  baseline:     before-state metric (e.g., 20-false-blocks/24h)" >&2
  echo "  finding_key:  dedup key as category:component (e.g., noise-reduction:stop-gate)" >&2
  exit 1
fi

category="$1"
description="$2"
data_sources="$3"
scope="$4"
baseline="${5:-}"
finding_key="${6:-${category}:unknown}"

# ── Validate category ────────────────────────────────────────────────
valid_categories=(
  "hook-coverage"
  "progressive-disclosure"
  "error-messages"
  "noise-reduction"
  "friction-reduction"
  "telemetry-quality"
  "test-gaps"
  "safety-corpus"
  "skill-quality"
  "prompt-quality"
  "regression-fix"
  "semantic-intelligence"
  "no-op"
)

category_valid=0
for vc in "${valid_categories[@]}"; do
  if [ "$category" = "$vc" ]; then
    category_valid=1
    break
  fi
done

if [ $category_valid -eq 0 ]; then
  echo "Error: invalid category '$category'" >&2
  echo "Valid categories: ${valid_categories[*]}" >&2
  exit 1
fi

# ── Build log entry ──────────────────────────────────────────────────
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

entry="[${ts}] [${category}] [${description}] [${data_sources}] [${scope}]"
if [ -n "$baseline" ]; then
  entry="${entry} [baseline:${baseline}]"
fi

# ── Append with flock ────────────────────────────────────────────────
log_dir="$(dirname "$LOG_FILE")"
mkdir -p "$log_dir" 2>/dev/null || true

(
  flock -w 5 200 || { echo "Warning: could not acquire lock, writing anyway" >&2; }
  printf '%s\n' "$entry" >> "$LOG_FILE"
) 200>"${LOG_FILE}.lock"

# ── Append to consumed-findings registry ─────────────────────────────
# Machine-parseable JSONL for dedup and before/after tracking
consumed_entry=$(printf '{"ts":"%s","finding_key":"%s","category":"%s","action":"%s","baseline":"%s","status":"pending_validation","description":"%s"}' \
  "$ts" "$finding_key" "$category" \
  "$([ "$category" = "no-op" ] && echo "no-op" || echo "fixed")" \
  "$baseline" \
  "$(printf '%s' "$description" | head -c 200 | tr '"' "'")")

(
  flock -w 5 201 || true
  printf '%s\n' "$consumed_entry" >> "$CONSUMED_FILE"
) 201>"${CONSUMED_FILE}.lock"

echo "Logged: $entry"
echo "Registry: $finding_key (pending_validation)"
