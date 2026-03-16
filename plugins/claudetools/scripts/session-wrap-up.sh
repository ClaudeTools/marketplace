#!/bin/bash
# Session wrap-up hook — fires on SessionEnd
# Spawns a background Claude session to run /wrap-up with conversation context.
#
# Loop prevention: CLAUDE_WRAP_UP env var is set on child sessions so their
# SessionEnd doesn't re-trigger this hook.

# Prevent infinite loop
[ "$CLAUDE_WRAP_UP" = "1" ] && exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# Skip if no session ID
[ -z "$SESSION_ID" ] && exit 0

LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)/logs/wrap-up"
mkdir -p "$LOG_DIR"
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

exit 0
