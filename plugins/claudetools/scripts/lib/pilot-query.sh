#!/usr/bin/env bash
# pilot-query.sh — Shared library for codebase-pilot queries
# Usage: source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/pilot-query.sh"
#        result=$(pilot_find_symbol "handleAuth")

# Guard against double-sourcing
[[ -n "${_PILOT_QUERY_LOADED:-}" ]] && return 0
_PILOT_QUERY_LOADED=1

# Auto-detect plugin root: env var > relative from this file's location
_PILOT_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
_PILOT_CLI="node ${_PILOT_ROOT}/codebase-pilot/dist/cli.js"

_pilot_project_root() {
  # Return project root: env var > git root > cwd
  if [[ -n "${CODEBASE_PILOT_PROJECT_ROOT:-}" ]]; then
    echo "$CODEBASE_PILOT_PROJECT_ROOT"
  elif git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null; then
    :
  else
    echo "${PWD}"
  fi
}

_pilot_run() {
  # Internal: run CLI command with project root set
  local cmd="$1"; shift
  CODEBASE_PILOT_PROJECT_ROOT="$(_pilot_project_root)" ${_PILOT_CLI} "$cmd" "$@"
}

pilot_ensure_index() {
  # Run index if DB doesn't exist yet
  local project_root
  project_root="$(_pilot_project_root)"
  if [[ ! -f "${project_root}/.codeindex/db.sqlite" ]]; then
    CODEBASE_PILOT_PROJECT_ROOT="$project_root" ${_PILOT_CLI} index >/dev/null 2>&1
  fi
}

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
