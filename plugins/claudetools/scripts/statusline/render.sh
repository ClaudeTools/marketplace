#!/usr/bin/env bash
# render.sh — claudetools statusline renderer
# Reads Claude Code JSON from stdin, outputs formatted status bar to stdout.
# Config: ~/.config/claudetools/statusline.json (falls back to bundled defaults)
#
# Features:
# - Visual progress bars using Unicode block characters
# - Peak/off-peak indicator (8am-2pm ET weekdays = peak)
# - Smart usage learning via P90 historical analysis
# - Color-coded bars: green → yellow → red based on usage percentage
set -euo pipefail

# Graceful degradation if jq is missing — output nothing
command -v jq &>/dev/null || { echo ""; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_CONFIG="$HOME/.config/claudetools/statusline.json"
DEFAULT_CONFIG="$SCRIPT_DIR/defaults.json"
HISTORY_FILE="$HOME/.config/claudetools/usage-history.jsonl"

# Load user config or create from defaults
if [[ ! -f "$USER_CONFIG" ]]; then
  mkdir -p "$(dirname "$USER_CONFIG")"
  cp "$DEFAULT_CONFIG" "$USER_CONFIG"
fi

CONFIG="$USER_CONFIG"

# Read JSON from stdin (Claude Code pipes session data)
INPUT=$(cat)

# Read config values
WIDGETS=$(jq -r '.widgets // ["model","git","context","session","weekly","peak","duration","worktree"] | .[]' "$CONFIG")
SEPARATOR=$(jq -r '.separator // " | "' "$CONFIG")
USE_COLORS=$(jq -r 'if .colors == false then "false" else "true" end' "$CONFIG")
BAR_WIDTH=$(jq -r '.bar_width // 10' "$CONFIG")

# --- Color helpers ---
if [[ "$USE_COLORS" == "true" ]]; then
  DIM='\033[2m'
  RESET='\033[0m'
  BOLD='\033[1m'
  CYAN='\033[36m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  MAGENTA='\033[35m'
  RED='\033[31m'
  BLUE='\033[34m'
  WHITE='\033[37m'
  BG_GREEN='\033[42m'
  BG_YELLOW='\033[43m'
  BG_RED='\033[41m'
  BG_BLUE='\033[44m'
  GRAY='\033[37m'
else
  DIM='' RESET='' BOLD='' CYAN='' GREEN='' YELLOW='' MAGENTA='' RED='' BLUE='' WHITE='' BG_GREEN='' BG_YELLOW='' BG_RED='' BG_BLUE='' GRAY=''
fi

# --- Progress bar renderer ---
# Usage: render_bar <percentage> <width> [label]
# Output: colored bar like [████████░░] 73%
render_bar() {
  local pct=${1:-0} width=${2:-10} label=${3:-""}
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))

  # Clamp
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  (( empty < 0 )) && empty=0

  # Color based on percentage
  local bar_color="$GREEN"
  if (( pct > 80 )); then
    bar_color="$RED"
  elif (( pct > 50 )); then
    bar_color="$YELLOW"
  fi

  # Build bar using Unicode blocks
  local bar=""
  local i
  for (( i = 0; i < filled; i++ )); do bar+="█"; done
  for (( i = 0; i < empty; i++ )); do bar+="░"; done

  if [[ -n "$label" ]]; then
    printf "${bar_color}%s${RESET}${GRAY}%s${RESET} ${bar_color}%d%%${RESET} %s" \
      "$(echo "$bar" | head -c $(( filled * 3 )))" \
      "$(echo "$bar" | tail -c +$(( filled * 3 + 1 )))" \
      "$pct" "$label"
  else
    printf "${bar_color}%s${RESET}${GRAY}%s${RESET} ${bar_color}%d%%${RESET}" \
      "$(echo "$bar" | head -c $(( filled * 3 )))" \
      "$(echo "$bar" | tail -c +$(( filled * 3 + 1 )))" \
      "$pct"
  fi
}

# --- Simpler bar: just colored filled + gray empty ---
simple_bar() {
  local pct=${1:-0} width=${2:-10}
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  (( empty < 0 )) && empty=0

  local bar_color="$GREEN"
  if (( pct > 80 )); then bar_color="$RED"
  elif (( pct > 50 )); then bar_color="$YELLOW"
  fi

  local filled_str="" empty_str=""
  local i
  for (( i = 0; i < filled; i++ )); do filled_str+="█"; done
  for (( i = 0; i < empty; i++ )); do empty_str+="░"; done

  printf "${bar_color}%s${RESET}${GRAY}%s${RESET}" "$filled_str" "$empty_str"
}

# --- Peak/off-peak detection ---
# Peak hours: 8am-2pm ET (13:00-19:00 UTC) on weekdays
# Source: Anthropic usage policy — peak times are ET-based, not user-local
is_peak_time() {
  local et_hour et_dow
  # Get current hour and day-of-week in America/New_York (ET)
  # TZ override is POSIX-standard and works on Linux/macOS
  et_hour=$(TZ='America/New_York' date +%H 2>/dev/null) || return 1
  et_dow=$(TZ='America/New_York' date +%u 2>/dev/null) || return 1  # 1=Mon, 7=Sun
  et_hour=$((10#$et_hour))  # Strip leading zero for arithmetic

  # Weekday (Mon-Fri = 1-5) AND 8am-2pm ET
  if (( et_dow >= 1 && et_dow <= 5 && et_hour >= 8 && et_hour < 14 )); then
    return 0  # Peak
  fi
  return 1  # Off-peak
}

# --- Smart usage learning ---
# Appends current session snapshot to history file for P90 analysis.
# Called on every render but only writes once per 5 minutes (debounced).
record_usage() {
  mkdir -p "$(dirname "$HISTORY_FILE")"
  local now
  now=$(date +%s)

  # Debounce: only record every 300 seconds
  if [[ -f "$HISTORY_FILE" ]]; then
    local last_ts
    last_ts=$(tail -1 "$HISTORY_FILE" 2>/dev/null | jq -r '.ts // 0' 2>/dev/null) || last_ts=0
    if (( now - last_ts < 300 )); then
      return
    fi
  fi

  # Extract current usage data (use effective ctx percentage, not raw)
  local five_pct seven_pct ctx_pct
  five_pct=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // 0' 2>/dev/null) || five_pct=0
  seven_pct=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // 0' 2>/dev/null) || seven_pct=0
  ctx_pct=$(echo "$INPUT" | jq -r '
    (.context_window.context_window_size // 200000) as $window |
    (.context_window.current_usage.input_tokens // 0) as $input |
    ($window - 20000 - 13000) as $effective |
    if $input > 0 and $effective > 0 then ($input / $effective * 100) | floor
    elif .context_window.used_percentage then .context_window.used_percentage | floor
    else 0 end
  ' 2>/dev/null) || ctx_pct=0

  local peak_flag="off-peak"
  is_peak_time && peak_flag="peak"

  # Append to history (keep it lean — just the essentials)
  printf '{"ts":%d,"5h":%s,"7d":%s,"ctx":%s,"peak":"%s"}\n' \
    "$now" "$five_pct" "$seven_pct" "$ctx_pct" "$peak_flag" \
    >> "$HISTORY_FILE" 2>/dev/null || true

  # Prune: keep only last 7 days (2016 entries at 5-min intervals)
  if [[ -f "$HISTORY_FILE" ]]; then
    local cutoff=$(( now - 604800 ))
    local tmp="${HISTORY_FILE}.tmp"
    jq -c "select(.ts >= $cutoff)" "$HISTORY_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$HISTORY_FILE" 2>/dev/null || rm -f "$tmp"
  fi
}

# --- P90 limit detection ---
# Reads history to compute the 90th percentile peak usage, which approximates
# the effective limit. Returns the P90 value or empty if insufficient data.
get_p90_limit() {
  local field=${1:-"5h"}  # "5h" or "7d"
  [[ ! -f "$HISTORY_FILE" ]] && return

  local count
  count=$(wc -l < "$HISTORY_FILE" 2>/dev/null) || count=0
  # Need at least 50 data points (~4 hours of data)
  (( count < 50 )) && return

  # Extract the field values, sort, and compute P90
  local p90
  p90=$(jq -r ".\"${field}\"" "$HISTORY_FILE" 2>/dev/null | sort -n | awk '
    { vals[NR] = $1 }
    END {
      idx = int(NR * 0.9)
      if (idx < 1) idx = 1
      print vals[idx]
    }
  ' 2>/dev/null) || return

  [[ -n "$p90" && "$p90" != "null" ]] && echo "$p90"
}

# --- Widget renderers ---

widget_model() {
  local name
  name=$(echo "$INPUT" | jq -r '.model.display_name // .model.id // empty') || return
  [[ -z "$name" ]] && return
  # Compact model name: strip " context", shorten "(1M context)" → "(1M)"
  name="${name/ context/}"
  name="${name/(1000000)/(1M)}"
  printf "${BOLD}%s${RESET}" "$name"
}

widget_git() {
  local branch
  branch=$(echo "$INPUT" | jq -r '.worktree.branch // empty' 2>/dev/null) || true
  if [[ -z "$branch" ]]; then
    branch=$(git --no-optional-locks branch --show-current 2>/dev/null) || branch=""
  fi
  [[ -z "$branch" ]] && return
  # Strip worktree prefix from branch name to avoid redundancy with worktree widget
  branch="${branch#worktree-}"
  printf "${CYAN}%s${RESET}" "$branch"
}

widget_context() {
  local raw_pct
  raw_pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')
  [[ -z "$raw_pct" || "$raw_pct" == "null" ]] && return

  # CC's used_percentage divides by the raw context_window_size, but the
  # usable window is smaller due to:
  #   - Output buffer: min(max_output_tokens, 20000) = 20K reserved for responses
  #   - Autocompact reserve: 13K tokens before the hard limit
  # This makes the displayed percentage lower than effective usage.
  # We correct by calculating against the effective (usable) window.
  #
  # See: github.com/anthropics/claude-code/issues/17959
  #      github.com/anthropics/claude-code/issues/18944
  local eff_pct tokens_k window_k
  read -r eff_pct tokens_k window_k <<< "$(echo "$INPUT" | jq -r '
    (.context_window.context_window_size // 200000) as $window |
    (.context_window.current_usage.input_tokens // 0) as $input |
    ($window - 20000 - 13000) as $effective |
    (if $input > 0 then $input
     elif .context_window.used_percentage then
       (.context_window.used_percentage / 100 * $window) | floor
     else 0 end) as $tokens |
    (if $effective > 0 then ($tokens / $effective * 100) | floor
     else 0 end) as $pct |
    (if $pct > 100 then 100 elif $pct < 0 then 0 else $pct end) as $clamped |
    # Format token counts as K or M
    (if $tokens >= 1000000 then (($tokens / 100000 | floor) / 10 | tostring) + "M"
     elif $tokens >= 1000 then (($tokens / 1000 | floor) | tostring) + "K"
     else ($tokens | tostring) end) as $tok_display |
    (if $effective >= 1000000 then (($effective / 100000 | floor) / 10 | tostring) + "M"
     elif $effective >= 1000 then (($effective / 1000 | floor) | tostring) + "K"
     else ($effective | tostring) end) as $win_display |
    "\($clamped) \($tok_display) \($win_display)"
  ')"

  local color
  color="$GREEN"; (( eff_pct > 50 )) && color="$YELLOW"; (( eff_pct > 80 )) && color="$RED"
  printf "%s ${color}%d%%${RESET} ${DIM}%s/%s ctx${RESET}" \
    "$(simple_bar "$eff_pct" "$BAR_WIDTH")" "$eff_pct" "$tokens_k" "$window_k"
}

widget_session() {
  local pct
  pct=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null) || true
  [[ -z "$pct" || "$pct" == "null" ]] && return
  local int_pct color reset_info
  int_pct=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage | floor')
  color="$GREEN"; (( int_pct > 50 )) && color="$YELLOW"; (( int_pct > 80 )) && color="$RED"
  reset_info=$(echo "$INPUT" | jq -r '
    .rate_limits.five_hour.resets_at // null |
    if . and . > 0 then
      (. | strflocaltime("%I:%M%p")) |
      # Strip leading zero, lowercase, drop minutes if :00
      ltrimstr("0") | ascii_downcase |
      gsub(":00";"") |
      " @" + .
    else "" end
  ' 2>/dev/null) || reset_info=""
  printf "%s ${color}%d%%${RESET} ${DIM}5h%s${RESET}" "$(simple_bar "$int_pct" "$BAR_WIDTH")" "$int_pct" "$reset_info"
}

widget_weekly() {
  local pct
  pct=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null) || true
  [[ -z "$pct" || "$pct" == "null" ]] && return
  local int_pct color reset_info
  int_pct=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage | floor')
  color="$GREEN"; (( int_pct > 50 )) && color="$YELLOW"; (( int_pct > 80 )) && color="$RED"
  reset_info=$(echo "$INPUT" | jq -r '
    .rate_limits.seven_day.resets_at // null |
    if . and . > 0 then
      (. | strflocaltime("%a")) as $day |
      (. | strflocaltime("%I:%M%p") | ltrimstr("0") | ascii_downcase | gsub(":00";"")) as $time |
      " @" + $day + " " + $time
    else "" end
  ' 2>/dev/null) || reset_info=""
  printf "%s ${color}%d%%${RESET} ${DIM}7d%s${RESET}" "$(simple_bar "$int_pct" "$BAR_WIDTH")" "$int_pct" "$reset_info"
}

widget_peak() {
  # Show peak/off-peak with the ET window converted to user's local timezone
  local local_start local_end
  # Convert 8am ET and 2pm ET to user-local time for display
  # TZ trick: set TZ to ET, create a date string, then format in local TZ
  local et_8am_utc et_2pm_utc
  # Get today's 8am ET and 2pm ET as epoch seconds
  et_8am_utc=$(TZ='America/New_York' date -d 'today 08:00' +%s 2>/dev/null) || true
  et_2pm_utc=$(TZ='America/New_York' date -d 'today 14:00' +%s 2>/dev/null) || true

  if [[ -n "$et_8am_utc" && -n "$et_2pm_utc" ]]; then
    # Format those UTC epochs in user's local timezone (12h, no leading zero)
    local_start=$(date -d "@$et_8am_utc" '+%-I%P' 2>/dev/null) || local_start="8am"
    local_end=$(date -d "@$et_2pm_utc" '+%-I%P' 2>/dev/null) || local_end="2pm"
  else
    # Fallback if date -d not available (macOS without coreutils)
    local_start="8am ET"
    local_end="2pm ET"
  fi

  if is_peak_time; then
    printf "${RED}▲ pk ${local_start}-${local_end}${RESET}"
  else
    printf "${GREEN}▽ off ${local_end}-${local_start}${RESET}"
  fi
}

widget_cost() {
  local cost
  cost=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // empty')
  [[ -z "$cost" || "$cost" == "null" || "$cost" == "0" ]] && return
  printf "${DIM}\$%s${RESET}" "$cost"
}

widget_speed() {
  local tps
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
  local wt_name branch
  wt_name=$(echo "$INPUT" | jq -r '.worktree.name // empty' 2>/dev/null) || true
  [[ -z "$wt_name" ]] && return
  # Skip if git widget already shows this info (branch contains worktree name)
  branch=$(echo "$INPUT" | jq -r '.worktree.branch // empty' 2>/dev/null) || true
  [[ "$branch" == *"$wt_name"* ]] && return
  printf "${MAGENTA}wt:%s${RESET}" "$wt_name"
}

widget_p90() {
  # Show P90 learned limit estimate if enough data exists
  local p90_5h p90_7d
  p90_5h=$(get_p90_limit "5h") || true
  p90_7d=$(get_p90_limit "7d") || true
  [[ -z "$p90_5h" && -z "$p90_7d" ]] && return
  local parts=""
  [[ -n "$p90_5h" ]] && parts="5h≈${p90_5h}%"
  [[ -n "$p90_7d" ]] && parts="${parts:+$parts }7d≈${p90_7d}%"
  printf "${DIM}P90:%s${RESET}" "$parts"
}

# --- Record usage for smart learning (best-effort, never blocks) ---
record_usage &>/dev/null &

# --- Build output ---
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
