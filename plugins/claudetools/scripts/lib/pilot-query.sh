#!/usr/bin/env bash
# pilot-query.sh — Shared library for srcpilot queries
# Usage: source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/pilot-query.sh"
#        result=$(pilot_find_symbol "handleAuth")

# Guard against double-sourcing
[[ -n "${_PILOT_QUERY_LOADED:-}" ]] && return 0
_PILOT_QUERY_LOADED=1

# Resolve the right srcpilot binary (global or plugin-local)
# shellcheck source=resolve-srcpilot.sh
source "${BASH_SOURCE[0]%/*}/resolve-srcpilot.sh"

# Detect availability once at source time
_SRCPILOT_AVAILABLE=0
command -v "$SRCPILOT" &>/dev/null && _SRCPILOT_AVAILABLE=1

_pilot_project_root() {
  # Return project root: env var > git root > cwd
  if [[ -n "${SRCPILOT_PROJECT_ROOT:-}" ]]; then
    echo "$SRCPILOT_PROJECT_ROOT"
  elif git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null; then
    :
  else
    echo "${PWD}"
  fi
}

_pilot_run() {
  # Internal: run CLI command with project root set
  [[ "$_SRCPILOT_AVAILABLE" -eq 0 ]] && return 1
  local cmd="$1"; shift
  SRCPILOT_PROJECT_ROOT="$(_pilot_project_root)" "$SRCPILOT" "$cmd" "$@"
}

pilot_ensure_index() {
  # Run index if DB doesn't exist yet
  [[ "$_SRCPILOT_AVAILABLE" -eq 0 ]] && return 1
  local project_root
  project_root="$(_pilot_project_root)"
  if [[ ! -f "${project_root}/.srcpilot/db.sqlite" ]]; then
    SRCPILOT_PROJECT_ROOT="$project_root" "$SRCPILOT" index >/dev/null 2>&1
  fi
}

# Returns 0 if srcpilot is available, 1 otherwise
pilot_available() { [[ "$_SRCPILOT_AVAILABLE" -eq 1 ]]; }

pilot_find_symbol()    { _pilot_run find-symbol "$@"; }
pilot_find_usages()    { _pilot_run find-usages "$@"; }
pilot_file_overview()  { _pilot_run file-overview "$@"; }
pilot_related_files()  { _pilot_run related-files "$@"; }
pilot_dead_code()      { _pilot_run dead-code "$@"; }
pilot_change_impact()  { _pilot_run change-impact "$@"; }
pilot_map()            { _pilot_run map "$@"; }
pilot_context_budget() { _pilot_run context-budget "$@"; }
pilot_api_surface()    { _pilot_run api-surface "$@"; }
pilot_circular_deps()  { _pilot_run circular-deps "$@"; }
pilot_navigate()       { _pilot_run navigate "$@"; }
pilot_doctor()         { _pilot_run doctor "$@"; }
