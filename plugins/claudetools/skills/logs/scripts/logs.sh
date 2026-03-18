#!/usr/bin/env bash
# logs.sh — Extract and query Claude Code JSONL session logs
# Usage: logs.sh [subcommand] [options]
# Subcommands: btw, search, tools, errors, conversation, summary (default)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/parse-jsonl.sh"

PROJECT_DIR=""
LAST_N=10
DATE_FILTER=""

# ---- Argument parsing helpers ----

parse_common_opts() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --last)  LAST_N="${2:-10}"; shift 2 ;;
      --all)   PROJECT_DIR="ALL"; shift ;;
      --session) SESSION_FILTER="${2:-}"; shift 2 ;;
      --project) PROJECT_DIR="${2:-}"; shift 2 ;;
      --from)  DATE_FILTER=$(parse_date_filter "${2:-today}"); shift 2 ;;
      *)       EXTRA_ARGS+=("$1"); shift ;;
    esac
  done
}

get_project_dirs() {
  if [ "$PROJECT_DIR" = "ALL" ]; then
    find "$HOME/.claude/projects" -maxdepth 1 -mindepth 1 -type d 2>/dev/null
  elif [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
    echo "$PROJECT_DIR"
  else
    local dir
    dir=$(resolve_project_dir)
    if [ -d "$dir" ]; then
      echo "$dir"
    fi
  fi
}

# ---- Subcommands ----

cmd_btw() {
  # Default to last 1 for btw (override before parse_common_opts)
  local btw_default_last=1
  local has_last=0
  for arg in "$@"; do [ "$arg" = "--last" ] && has_last=1; done
  [ "$has_last" -eq 0 ] && LAST_N=$btw_default_last

  parse_common_opts "$@"
  local count=0

  # Collect all btw files across projects, sorted newest first
  local btw_files=()
  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue
    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue
      local sid sdir
      sid=$(session_id_from_path "$session_file")
      sdir=$(session_dir_for "$session_file")
      [ -n "${SESSION_FILTER:-}" ] && [[ "$sid" != *"$SESSION_FILTER"* ]] && continue
      while IFS= read -r btw_file; do
        [ -z "$btw_file" ] && continue
        [ -n "$DATE_FILTER" ] && ! session_after_date "$btw_file" "$DATE_FILTER" && continue
        btw_files+=("$btw_file")
      done < <(list_subagents "$sdir" "agent-aside_question-*.jsonl")
    done < <(list_sessions "$pdir")
  done < <(get_project_dirs)

  if [ ${#btw_files[@]} -eq 0 ]; then
    echo "No /btw conversations found."
    return
  fi

  # Show requested number of btw conversations
  for btw_file in "${btw_files[@]}"; do
    [ "$count" -ge "$LAST_N" ] && break
    count=$((count + 1))

    # Extract Q and A in one jq pass
    local qa
    qa=$(jq -r '
      select(.type == "user" or .type == "assistant") |
      .type as $t |
      (.message.content // "") |
      (if type == "array" then [.[] | select(.type == "text") | .text] | join("\n")
       elif type == "string" then .
       else tostring end) |
      if . != "" then
        if $t == "user" then "Q: " + .
        else "A: " + .
        end
      else empty end
    ' "$btw_file" 2>/dev/null)

    [ -z "$qa" ] && continue

    # Strip system reminders
    qa=$(echo "$qa" | sed ':a;N;$!ba;s/<system-reminder>[^<]*<\/system-reminder>//g' | sed '/^$/d')

    if [ "$LAST_N" -gt 1 ]; then
      local ts
      ts=$(first_timestamp "$btw_file")
      echo "--- $(format_timestamp "${ts:-unknown}") ---"
    fi
    echo "$qa"
    [ "$LAST_N" -gt 1 ] && echo ""
  done

  [ ${#btw_files[@]} -gt "$LAST_N" ] && echo "(${#btw_files[@]} total, showing $LAST_N)"
}

cmd_search() {
  parse_common_opts "$@"
  local term="${EXTRA_ARGS[0]:-}"
  if [ -z "$term" ]; then
    echo "Usage: logs.sh search <term> [--last N]"
    return
  fi

  local count=0

  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue

    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue
      [ "$count" -ge "$LAST_N" ] && break

      local sid
      sid=$(session_id_from_path "$session_file")
      [ -n "${SESSION_FILTER:-}" ] && [[ "$sid" != *"$SESSION_FILTER"* ]] && continue
      [ -n "$DATE_FILTER" ] && ! session_after_date "$session_file" "$DATE_FILTER" && continue

      # Search for term in the file
      if ! grep -qi "$term" "$session_file" 2>/dev/null; then
        continue
      fi

      # Extract matching exchanges
      local found_in_session=0
      jq -c "select(.type == \"user\" or .type == \"assistant\") | select(.message.content != null)" "$session_file" 2>/dev/null | while IFS= read -r entry; do
        local content text
        content=$(echo "$entry" | jq -c '.message.content' 2>/dev/null)
        text=$(extract_text "$content")

        if echo "$text" | grep -qi "$term" 2>/dev/null; then
          if [ "$found_in_session" -eq 0 ]; then
            local ts
            ts=$(first_timestamp "$session_file")
            echo "--- Session: ${sid:0:8} ($(format_timestamp "${ts:-unknown}")) ---"
            echo ""
            found_in_session=1
          fi

          local etype ets
          etype=$(echo "$entry" | jq -r '.type' 2>/dev/null)
          ets=$(echo "$entry" | jq -r '.timestamp // ""' 2>/dev/null)
          local label="Q"
          [ "$etype" = "assistant" ] && label="A"
          echo "[$(format_timestamp "$ets")] ${label}: $(truncate_text "$text" 300)"
        fi
      done

      count=$((count + 1))
    done < <(list_sessions "$pdir")
  done < <(get_project_dirs)

  [ "$count" -eq 0 ] && echo "No matches found for \"${term}\"."
}

cmd_tools() {
  parse_common_opts "$@"
  local count=0

  echo "Tool Usage Summary"
  echo "=================="
  echo ""

  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue

    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue
      [ "$count" -ge "$LAST_N" ] && break

      local sid
      sid=$(session_id_from_path "$session_file")
      [ -n "${SESSION_FILTER:-}" ] && [[ "$sid" != *"$SESSION_FILTER"* ]] && continue
      [ -n "$DATE_FILTER" ] && ! session_after_date "$session_file" "$DATE_FILTER" && continue

      local ts
      ts=$(first_timestamp "$session_file")
      local tools
      tools=$(grep '"tool_use"' "$session_file" 2>/dev/null | jq -r '.message.content // [] | if type == "array" then .[] else empty end | select(.type == "tool_use") | .name' 2>/dev/null | sort | uniq -c | sort -rn | head -15)

      if [ -n "$tools" ]; then
        echo "--- Session: ${sid:0:8} ($(format_timestamp "${ts:-unknown}")) ---"
        echo "$tools" | while IFS= read -r line; do
          echo "  $line"
        done
        echo ""
        count=$((count + 1))
      fi
    done < <(list_sessions "$pdir")
  done < <(get_project_dirs)

  [ "$count" -eq 0 ] && echo "No tool usage data found."
}

cmd_errors() {
  parse_common_opts "$@"
  local count=0

  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue

    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue
      [ "$count" -ge "$LAST_N" ] && break

      local sid
      sid=$(session_id_from_path "$session_file")
      [ -n "${SESSION_FILTER:-}" ] && [[ "$sid" != *"$SESSION_FILTER"* ]] && continue
      [ -n "$DATE_FILTER" ] && ! session_after_date "$session_file" "$DATE_FILTER" && continue

      # Look for error entries
      local errors
      errors=$(jq -c 'select(.type == "assistant") | .message.content // [] | if type == "array" then .[] else empty end | select(.type == "tool_result" and .is_error == true)' "$session_file" 2>/dev/null | head -20)

      if [ -n "$errors" ]; then
        local ts
        ts=$(first_timestamp "$session_file")
        echo "--- Session: ${sid:0:8} ($(format_timestamp "${ts:-unknown}")) ---"
        echo ""
        echo "$errors" | while IFS= read -r err; do
          local tool_id content
          tool_id=$(echo "$err" | jq -r '.tool_use_id // "unknown"' 2>/dev/null)
          content=$(echo "$err" | jq -r '.content // "no message"' 2>/dev/null)
          echo "  ERROR (${tool_id:0:12}): $(truncate_text "$content" 200)"
        done
        echo ""
        count=$((count + 1))
      fi
    done < <(list_sessions "$pdir")
  done < <(get_project_dirs)

  [ "$count" -eq 0 ] && echo "No errors found in recent sessions."
}

cmd_conversation() {
  parse_common_opts "$@"
  local target_session="${EXTRA_ARGS[0]:-}"

  if [ -z "$target_session" ]; then
    # Default to most recent session
    local pdir
    pdir=$(get_project_dirs | head -1)
    if [ -z "$pdir" ]; then
      echo "No project directory found."
      return
    fi
    local latest
    latest=$(list_sessions "$pdir" | head -1)
    if [ -z "$latest" ]; then
      echo "No sessions found."
      return
    fi
    target_session=$(session_id_from_path "$latest")
  fi

  local count=0

  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue

    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue

      local sid
      sid=$(session_id_from_path "$session_file")
      [[ "$sid" != *"$target_session"* ]] && continue
      [ -n "$DATE_FILTER" ] && ! session_after_date "$session_file" "$DATE_FILTER" && continue

      local ts
      ts=$(first_timestamp "$session_file")
      echo "=== Session: ${sid} ($(format_timestamp "${ts:-unknown}")) ==="
      echo ""

      jq -c 'select(.type == "user" or .type == "assistant")' "$session_file" 2>/dev/null | while IFS= read -r entry; do
        local etype ets content text
        etype=$(echo "$entry" | jq -r '.type' 2>/dev/null)
        ets=$(echo "$entry" | jq -r '.timestamp // ""' 2>/dev/null)
        content=$(echo "$entry" | jq -c '.message.content // ""' 2>/dev/null)
        text=$(extract_text "$content")
        text=$(strip_system_reminders "$text")
        [ -z "$text" ] && continue

        count=$((count + 1))
        [ "$count" -gt "$LAST_N" ] && break

        local label="USER"
        [ "$etype" = "assistant" ] && label="CLAUDE"
        echo "[$(format_timestamp "$ets")] ${label}:"
        echo "$(truncate_text "$text" 800)"
        echo ""
      done
      break
    done < <(list_sessions "$pdir")
  done < <(get_project_dirs)

  [ "$count" -eq 0 ] && echo "No conversation found for session matching \"${target_session}\"."
}

cmd_summary() {
  parse_common_opts "$@"
  local count=0

  echo "Session Summary"
  echo "==============="
  echo ""

  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue
    local pname
    pname=$(basename "$pdir")

    while IFS= read -r session_file; do
      [ -z "$session_file" ] && continue
      [ "$count" -ge "$LAST_N" ] && break

      [ -n "$DATE_FILTER" ] && ! session_after_date "$session_file" "$DATE_FILTER" && continue

      local sid ts user_count tool_count file_size
      sid=$(session_id_from_path "$session_file")
      ts=$(first_timestamp "$session_file")
      user_count=$(grep -c '"type":"user"' "$session_file" 2>/dev/null || echo "0")
      tool_count=$(grep -c '"tool_use"' "$session_file" 2>/dev/null || echo "0")
      file_size=$(du -h "$session_file" 2>/dev/null | cut -f1)

      # Get first user message as topic hint
      local topic
      topic=$(grep -m1 '"type":"user"' "$session_file" 2>/dev/null | jq -r '.message.content // "" | if type == "string" then .[:80] else "" end' 2>/dev/null || true)

      local date_str
      date_str=$(format_timestamp "${ts:-unknown}")

      printf "%-8s  %-16s  %3s turns  %4s tools  %5s  %s\n" \
        "${sid:0:8}" "$date_str" "$user_count" "$tool_count" "$file_size" "${topic:0:50}"

      count=$((count + 1))
    done < <(list_sessions "$pdir")
  done < <(get_project_dirs)

  [ "$count" -eq 0 ] && echo "No sessions found."
}

cmd_help() {
  cat <<'USAGE'
Usage: logs.sh [subcommand] [options]

Subcommands:
  summary              Session overview: turns, tools, size (default)
  btw                  /btw side-question Q&A history
  search <term>        Search across session logs for a term
  tools                Tool usage summary per session
  errors               Extract errors and failed tool calls
  conversation [id]    Full user/assistant exchanges for a session

Options:
  --last N             Show last N results (default: 10)
  --all                Search all projects, not just current
  --session ID         Filter to a specific session (partial match)
  --from VALUE         Filter by date: today, yesterday, "N days ago", "this week", YYYY-MM-DD
  --help               Show this help

Examples:
  logs.sh                             # summary of last 10 sessions
  logs.sh btw --last 5                # last 5 /btw conversations
  logs.sh btw --all --from today      # all /btw conversations from today
  logs.sh search "memory" --from yesterday  # search "memory" since yesterday
  logs.sh tools --session abc123      # tool usage for a specific session
  logs.sh summary --from 2026-03-15   # sessions since a specific date
  logs.sh errors --all                # errors across all projects
USAGE
}

# ---- Main routing ----

EXTRA_ARGS=()
SESSION_FILTER=""
SUBCOMMAND="${1:-summary}"
shift 2>/dev/null || true

case "$SUBCOMMAND" in
  btw)          cmd_btw "$@" ;;
  search)       cmd_search "$@" ;;
  tools)        cmd_tools "$@" ;;
  errors)       cmd_errors "$@" ;;
  conversation) cmd_conversation "$@" ;;
  summary)      cmd_summary "$@" ;;
  --help|-h|help) cmd_help ;;
  *)
    echo "Unknown subcommand: $SUBCOMMAND"
    echo ""
    cmd_help
    ;;
esac

exit 0
