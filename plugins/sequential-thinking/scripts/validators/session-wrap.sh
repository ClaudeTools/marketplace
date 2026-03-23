#!/bin/bash
# Validator: session wrap-up runner
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 always (side-effect runner)

run_session_wrap() {
  # Prevent infinite loop
  [ "$CLAUDE_WRAP_UP" = "1" ] && return 0

  local SESSION_ID
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
  local CWD
  CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
  local TRANSCRIPT
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

  # Skip if no session ID
  [ -z "$SESSION_ID" ] && return 0

  local LOG_DIR
  LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/logs/wrap-up"
  mkdir -p "$LOG_DIR"
  local LOG_FILE
  LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d_%H%M%S).log"

  (
    # Unset CLAUDECODE to allow nested session
    unset CLAUDECODE
    export CLAUDE_WRAP_UP=1

    # Wait for transcript to be written (up to 10 seconds)
    for i in $(seq 1 10); do
      [ -f "$TRANSCRIPT" ] && break
      sleep 1
    done

    cd "$CWD" || exit 1

    if [ -f "$TRANSCRIPT" ]; then
      # Resume the session with full context and run wrap-up
      claude --resume "$SESSION_ID" \
        -p "Run /wrap-up" \
        --permission-mode acceptEdits \
        --no-session-persistence \
        >> "$LOG_FILE" 2>&1
    else
      # Transcript not available — log and exit. Never auto-commit without user consent.
      echo "Transcript not found at $TRANSCRIPT — skipping wrap-up (no auto-commit without consent)" > "$LOG_FILE"
    fi
  ) &
  disown

  return 0
}
