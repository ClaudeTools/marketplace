#!/usr/bin/env bash
# render.sh — claudetools statusline renderer
# Reads Claude Code JSON from stdin, outputs formatted status bar to stdout.
# Config: ~/.config/claudetools/statusline.json (falls back to bundled defaults)
set -euo pipefail

# Graceful degradation if jq is missing — output nothing
command -v jq &>/dev/null || { echo ""; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_CONFIG="$HOME/.config/claudetools/statusline.json"
DEFAULT_CONFIG="$SCRIPT_DIR/defaults.json"

# Load user config or create from defaults
if [[ ! -f "$USER_CONFIG" ]]; then
  mkdir -p "$(dirname "$USER_CONFIG")"
  cp "$DEFAULT_CONFIG" "$USER_CONFIG"
fi

CONFIG="$USER_CONFIG"

# Read JSON from stdin (Claude Code pipes session data)
INPUT=$(cat)

# Read config values
WIDGETS=$(jq -r '.widgets // ["model","git","context","cost","speed","duration","worktree"] | .[]' "$CONFIG")
SEPARATOR=$(jq -r '.separator // " | "' "$CONFIG")
USE_COLORS=$(jq -r 'if .colors == false then "false" else "true" end' "$CONFIG")

# Color helpers
if [[ "$USE_COLORS" == "true" ]]; then
  DIM='\033[2m'
  RESET='\033[0m'
  BOLD='\033[1m'
  CYAN='\033[36m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  MAGENTA='\033[35m'
  RED='\033[31m'
else
  DIM='' RESET='' BOLD='' CYAN='' GREEN='' YELLOW='' MAGENTA='' RED=''
fi

# Widget renderers — each reads from $INPUT and prints a string
widget_model() {
  local name
  name=$(echo "$INPUT" | jq -r '.model.display_name // .model.id // empty') || return
  [[ -z "$name" ]] && return
  printf "${BOLD}%s${RESET}" "$name"
}

widget_git() {
  local branch
  branch=$(echo "$INPUT" | jq -r '.worktree.branch // empty' 2>/dev/null) || true
  if [[ -z "$branch" ]]; then
    branch=$(git --no-optional-locks branch --show-current 2>/dev/null) || branch=""
  fi
  [[ -z "$branch" ]] && return
  printf "${CYAN}%s${RESET}" "$branch"
}

widget_context() {
  local pct color
  pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')
  [[ -z "$pct" || "$pct" == "null" ]] && return
  # Use jq for integer comparison (avoids bc dependency)
  local int_pct
  int_pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage | floor')
  color="$GREEN"
  if (( int_pct > 80 )); then
    color="$RED"
  elif (( int_pct > 50 )); then
    color="$YELLOW"
  fi
  printf "${color}%d%% ctx${RESET}" "$int_pct"
}

widget_cost() {
  local cost
  cost=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // empty')
  [[ -z "$cost" || "$cost" == "null" || "$cost" == "0" ]] && return
  printf "${DIM}\$%s${RESET}" "$cost"
}

widget_speed() {
  local tps
  # Use jq to compute tok/s as integer, avoiding bc dependency
  tps=$(echo "$INPUT" | jq -r '
    ((.context_window.total_output_tokens // 0) | tonumber) as $tok |
    ((.cost.total_api_duration_ms // 0) | tonumber) as $ms |
    if $ms > 0 then (($tok / ($ms / 1000)) * 10 | floor / 10 | tostring)
    else empty end
  ' 2>/dev/null) || true
  [[ -z "$tps" ]] && return
  printf "${DIM}%s tok/s${RESET}" "$tps"
}

widget_duration() {
  local ms mins
  ms=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // empty')
  [[ -z "$ms" || "$ms" == "null" || "$ms" == "0" ]] && return
  mins=$(( ms / 60000 ))
  if (( mins >= 60 )); then
    printf "${DIM}%dh%dm${RESET}" $(( mins / 60 )) $(( mins % 60 ))
  elif (( mins > 0 )); then
    printf "${DIM}%dm${RESET}" "$mins"
  else
    printf "${DIM}<1m${RESET}"
  fi
}

widget_worktree() {
  local wt_name
  wt_name=$(echo "$INPUT" | jq -r '.worktree.name // empty' 2>/dev/null) || true
  [[ -z "$wt_name" ]] && return
  printf "${MAGENTA}wt:%s${RESET}" "$wt_name"
}

# Build output
parts=()
for w in $WIDGETS; do
  result=$(widget_"$w" 2>/dev/null) || true
  [[ -n "$result" ]] && parts+=("$result")
done

# Join with separator
output=""
for i in "${!parts[@]}"; do
  (( i > 0 )) && output+="$SEPARATOR"
  output+="${parts[$i]}"
done

printf '%b' "$output"
