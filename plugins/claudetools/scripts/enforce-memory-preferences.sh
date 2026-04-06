#!/bin/bash
# PreToolUse:Edit|Write|Bash — Enforce memory-stored preferences
# Checks if the agent's current action contradicts a stored feedback memory.
# Warns (exit 1) with the matching rule; never blocks.
# Designed for <100ms execution: caches directives per session in /tmp.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/hook-input.sh"
source "$SCRIPT_DIR/lib/worktree.sh"
hook_init

HOOK_DECISION="allow"
HOOK_REASON=""

# --- Resolve memory index ---
# CWD from hook input (the project working directory)
CWD=$(hook_get_field '.cwd')
[ -z "$CWD" ] && CWD="$(pwd)"

# Resolve memory path — use get_repo_root() to handle worktrees correctly.
REPO_ROOT=$(get_repo_root)
PROJECT_SLUG=$(echo "$REPO_ROOT" | sed 's|^/|-|; s|/|-|g')
MEMORY_INDEX="$HOME/.claude/projects/${PROJECT_SLUG}/memory/MEMORY.md"
hook_log "memory-prefs: CWD=$CWD REPO_ROOT=$REPO_ROOT SLUG=$PROJECT_SLUG EXISTS=$([ -f "$MEMORY_INDEX" ] && echo yes || echo no)"

# If memory index doesn't exist, nothing to enforce
if [ ! -f "$MEMORY_INDEX" ]; then
  exit 0
fi

# --- Cache directives per session ---
SESSION_ID=$(hook_get_field '.session_id')
[ -z "$SESSION_ID" ] && SESSION_ID="default"
CACHE_FILE="/tmp/.claude-memory-directives-${SESSION_ID}"

if [ ! -f "$CACHE_FILE" ] || [ "$MEMORY_INDEX" -nt "$CACHE_FILE" ]; then
  # Extract feedback memory lines that contain strong directives
  # Each line in MEMORY.md looks like: - [filename.md](filename.md) — description
  # We want the description part after the — separator
  grep -iE '(ALWAYS|NEVER|never|always|don'\''t|must|DO NOT)' "$MEMORY_INDEX" \
    | sed 's/^.*— //' \
    > "$CACHE_FILE" 2>/dev/null || true
fi

# If no directives cached, nothing to enforce
[ -s "$CACHE_FILE" ] || exit 0

# --- Extract tool context ---
TOOL_NAME=$(hook_get_field '.tool_name')
COMMAND=$(hook_get_field '.tool_input.command')
CONTENT=$(hook_get_field '.tool_input.new_string // .tool_input.content')

# Combine all input text for keyword matching (lowercase for case-insensitive matching)
TOOL_CONTEXT=$(printf '%s\n%s\n%s' "$TOOL_NAME" "$COMMAND" "$CONTENT" | tr '[:upper:]' '[:lower:]')

# --- Check each directive against current action ---
check_contradiction() {
  local directive="$1"
  local directive_lower
  directive_lower=$(echo "$directive" | tr '[:upper:]' '[:lower:]')

  # Rule: "ALWAYS use CreateTeam agents for code changes — never edit files directly"
  # Triggers when: Edit or Write is used from a non-agent (main conversation)
  if echo "$directive_lower" | grep -qE 'always use.*agent|always use.*createteam|always use.*team'; then
    if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
      local agent_type
      agent_type=$(hook_get_field '.agent_type')
      if [[ "$agent_type" == "main" || -z "$agent_type" ]]; then
        echo "$directive"
        return 0
      fi
    fi
  fi

  # Rule: "Never use hardcoded Tailwind color classes"
  # Triggers when: writing content with hardcoded color classes
  if echo "$directive_lower" | grep -qE 'hardcoded.*color|hardcoded.*tailwind|never.*hardcoded.*color'; then
    if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]]; then
      if echo "$CONTENT" | grep -qE '(text-white|text-black|bg-white|bg-black|bg-zinc-[0-9]|bg-gray-[0-9]|bg-slate-[0-9]|text-gray-[0-9]|text-zinc-[0-9]|text-slate-[0-9])' 2>/dev/null; then
        echo "$directive"
        return 0
      fi
    fi
  fi

  # Rule: "Only run tests relevant to changed files — never run the full suite"
  # Triggers when: Bash runs a full test suite command
  if echo "$directive_lower" | grep -qE 'only run.*relevant|targeted tests|never.*full.*suite'; then
    if [[ "$TOOL_NAME" == "Bash" ]]; then
      if echo "$COMMAND" | grep -qE '(npm test$|yarn test$|pytest$|run-tests\.sh all|bats tests/$)' 2>/dev/null; then
        echo "$directive"
        return 0
      fi
    fi
  fi

  # Rule: "Do not want tests run during implementation"
  # Triggers when: Bash runs test commands
  if echo "$directive_lower" | grep -qE 'not want tests|no tests|don.t run tests'; then
    if [[ "$TOOL_NAME" == "Bash" ]]; then
      if echo "$COMMAND" | grep -qE '(npm test|yarn test|pytest|bats |vitest|jest |run-tests)' 2>/dev/null; then
        echo "$directive"
        return 0
      fi
    fi
  fi

  # Rule: "Never delete/remove files without permission"
  # Triggers when: Bash uses rm commands
  if echo "$directive_lower" | grep -qE 'never delete|never remove|never.*rm'; then
    if [[ "$TOOL_NAME" == "Bash" ]]; then
      if echo "$COMMAND" | grep -qE '\brm\b' 2>/dev/null; then
        echo "$directive"
        return 0
      fi
    fi
  fi

  # Rule: "Always create tasks before spawning agents"
  # Triggers when: Agent tool is used (caught by Edit|Write|Bash matcher only if Bash spawns agent)
  if echo "$directive_lower" | grep -qE 'always create tasks.*before|task.*before.*agent|task.*manager.*first'; then
    if [[ "$TOOL_NAME" == "Bash" ]]; then
      if echo "$COMMAND" | grep -qE '(createteam|create.*team|spawn.*agent)' 2>/dev/null; then
        echo "$directive"
        return 0
      fi
    fi
  fi

  # Rule: "Never work directly on master/main" (branch-before-work)
  if echo "$directive_lower" | grep -qE 'never.*directly on (master|main)|branch before|create.*branch.*first'; then
    if [[ "$TOOL_NAME" == "Bash" ]]; then
      if echo "$COMMAND" | grep -qE 'git (commit|push)' 2>/dev/null; then
        # Check if on main/master
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
          echo "$directive"
          return 0
        fi
      fi
    fi
  fi

  return 1
}

# Read cached directives and check each one
while IFS= read -r directive; do
  [ -z "$directive" ] && continue
  match=$(check_contradiction "$directive") || continue
  if [ -n "$match" ]; then
    HOOK_DECISION="warn"
    HOOK_REASON="$match"
    # Emit warning as systemMessage
    warning="MEMORY PREFERENCE CONFLICT: Your action may contradict a stored preference: \"${match}\". Review and proceed only if intentional."
    echo "{\"systemMessage\":$(echo "$warning" | jq -Rs .)}"
    record_hook_outcome "enforce-memory-preferences" "PreToolUse" "warn" "$TOOL_NAME" "" "" "$MODEL_FAMILY" 2>/dev/null || true
    emit_event "enforce-memory-preferences" "memory_conflict" "warn" "" "{\"directive\":$(echo "$match" | jq -Rs .)}" 2>/dev/null || true
    exit 0
  fi
done < "$CACHE_FILE"

record_hook_outcome "enforce-memory-preferences" "PreToolUse" "allow" "$TOOL_NAME" "" "" "$MODEL_FAMILY" 2>/dev/null || true
exit 0
