#!/usr/bin/env bash
# parse-jsonl.sh — Shared functions for extracting content from Claude Code JSONL session files
# Source this file; do not execute directly.

# Derive the Claude Code project directory from the current working directory.
# Claude Code encodes paths as: /home/user/project → -home-user-project
resolve_project_dir() {
  local cwd="${1:-$PWD}"
  local slug
  slug=$(echo "$cwd" | sed 's|^/|-|' | tr '/' '-')
  echo "$HOME/.claude/projects/${slug}"
}

# Extract plain text from a message.content field (JSON value passed as string).
# Handles both string content and array-of-blocks [{type:"text", text:"..."}] format.
extract_text() {
  local json_content="$1"
  if [ -z "$json_content" ] || [ "$json_content" = "null" ]; then
    echo ""
    return
  fi
  # Detect type: string vs array
  local ctype
  ctype=$(echo "$json_content" | jq -r 'type' 2>/dev/null)
  case "$ctype" in
    string)
      echo "$json_content" | jq -r '.' 2>/dev/null
      ;;
    array)
      echo "$json_content" | jq -r '[.[] | select(.type == "text") | .text] | join("\n")' 2>/dev/null
      ;;
    *)
      echo "$json_content" | jq -r 'tostring' 2>/dev/null
      ;;
  esac
}

# Remove <system-reminder>...</system-reminder> blocks from text.
strip_system_reminders() {
  local text="$1"
  echo "$text" | sed ':a;N;$!ba;s/<system-reminder>[^<]*<\/system-reminder>//g' | sed '/^$/d'
}

# List session JSONL files for a project, sorted newest first.
# Args: [project_dir] (defaults to resolve_project_dir output)
list_sessions() {
  local project_dir="${1:-$(resolve_project_dir)}"
  if [ ! -d "$project_dir" ]; then
    return
  fi
  # Session files are UUIDs at the project root
  find "$project_dir" -maxdepth 1 -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | \
    sort -rn | cut -d' ' -f2-
}

# List subagent JSONL files for a session directory, optionally filtered.
# Args: session_dir [filename_pattern]
list_subagents() {
  local session_dir="$1"
  local pattern="${2:-*.jsonl}"
  local subagent_dir="${session_dir}/subagents"
  if [ ! -d "$subagent_dir" ]; then
    return
  fi
  find "$subagent_dir" -maxdepth 1 -name "$pattern" -type f -printf '%T@ %p\n' 2>/dev/null | \
    sort -rn | cut -d' ' -f2-
}

# Get the session directory for a given JSONL file (strips the .jsonl, that's the session dir)
session_dir_for() {
  local jsonl_file="$1"
  echo "${jsonl_file%.jsonl}"
}

# Extract session ID (UUID) from a JSONL file path
session_id_from_path() {
  local jsonl_file="$1"
  basename "$jsonl_file" .jsonl
}

# Get the first timestamp from a JSONL file (used for sorting/display)
first_timestamp() {
  local jsonl_file="$1"
  head -20 "$jsonl_file" 2>/dev/null | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null | head -1
}

# Format an ISO timestamp to a short display format: YYYY-MM-DD HH:MM
format_timestamp() {
  local ts="$1"
  echo "$ts" | sed 's/T/ /;s/\.[0-9]*Z$//' | cut -c1-16
}

# Truncate text to a max length, appending "..." if truncated
truncate_text() {
  local text="$1"
  local max="${2:-500}"
  if [ ${#text} -le "$max" ]; then
    echo "$text"
  else
    echo "${text:0:$max}..."
  fi
}
