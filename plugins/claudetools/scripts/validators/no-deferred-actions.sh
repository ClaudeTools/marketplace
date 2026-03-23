#!/bin/bash
# Validator: detect when agent lists manual steps instead of executing them
# Sourced by dispatchers after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = clean, 2 = deferred actions detected (block)

validate_no_deferred_actions() {
  # Get the agent's output/transcript text from available fields
  local TEXT=""
  TEXT=$(hook_get_field '.tool_response.content' 2>/dev/null || true)
  [ -z "$TEXT" ] && TEXT=$(hook_get_field '.result' 2>/dev/null || true)
  [ -z "$TEXT" ] && TEXT=$(hook_get_field '.content' 2>/dev/null || true)

  # Also check transcript if available
  local TRANSCRIPT_PATH
  TRANSCRIPT_PATH=$(hook_get_field '.transcript_path' 2>/dev/null || true)
  if [ -z "$TEXT" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Get the last assistant message from transcript (last 200 lines)
    TEXT=$(tail -200 "$TRANSCRIPT_PATH" 2>/dev/null || true)
  fi

  # Nothing to check
  [ -z "$TEXT" ] && return 0

  # Count deferred action patterns — imperative commands directed at the user
  local DEFERRED_COUNT=0
  local DEFERRED_EXAMPLES=""

  # Pattern 1: "Run `command`" or "Execute `command`" at start of line
  local P1
  P1=$(echo "$TEXT" | grep -ciE '^\s*(Run|Execute|Now run|Then run|Finally,? run|Next,? run)\s+`' 2>/dev/null) || P1=0
  DEFERRED_COUNT=$((DEFERRED_COUNT + P1))

  # Pattern 2: "You can/should/need to run/execute/push/deploy"
  local P2
  P2=$(echo "$TEXT" | grep -ciE '^\s*(You (can|should|need to|must|will need to)|Please)\s+(run|execute|push|deploy|merge|publish|start)' 2>/dev/null) || P2=0
  DEFERRED_COUNT=$((DEFERRED_COUNT + P2))

  # Pattern 3: "To verify/test/deploy, run `command`"
  local P3
  P3=$(echo "$TEXT" | grep -ciE '^\s*To (verify|test|deploy|publish|complete|finish|confirm),?\s+(run|execute|use)' 2>/dev/null) || P3=0
  DEFERRED_COUNT=$((DEFERRED_COUNT + P3))

  # Pattern 4: "Next step(s):" followed by commands — header detection
  local P4
  P4=$(echo "$TEXT" | grep -ciE '^\s*(Next steps?|Manual steps?|Remaining steps?|TODO|Action items?):' 2>/dev/null) || P4=0
  DEFERRED_COUNT=$((DEFERRED_COUNT + P4))

  # Pattern 5: "Go to/Visit/Open the X dashboard/console/UI" — deferring to any GUI
  local P5
  P5=$(echo "$TEXT" | grep -ciE '(Go to|Visit|Open|Navigate to)\s+(the |your )?\w+\s+(dashboard|console|UI|portal|settings|panel|admin|control panel)' 2>/dev/null) || P5=0
  DEFERRED_COUNT=$((DEFERRED_COUNT + P5))

  # Pattern 6: Imperative infra verbs at line start without a tool call
  local P6
  P6=$(echo "$TEXT" | grep -ciE '^\s*(Add|Create|Update|Set up|Configure|Enable|Apply|Migrate|Deploy|Provision)\s+(a |the |your )?\w' 2>/dev/null) || P6=0
  # Only count if 3+ of these — a single "Add a comment" is normal
  [ "$P6" -lt 3 ] && P6=0
  DEFERRED_COUNT=$((DEFERRED_COUNT + P6))

  # Threshold: 2+ patterns = likely deferring real work (1 might be documentation)
  if [ "$DEFERRED_COUNT" -ge 2 ]; then
    # Grab examples for the block message
    DEFERRED_EXAMPLES=$(echo "$TEXT" | grep -iE '^\s*(Run |Execute |You (can|should|need)|To (verify|test|deploy)|Next steps?:|Go to |Visit |Navigate to )' 2>/dev/null | head -3 | sed 's/^/  /')

    echo "You listed $DEFERRED_COUNT step(s) for the user instead of executing them yourself — this breaks the autonomous workflow and forces manual intervention." >&2
    if [ -n "$DEFERRED_EXAMPLES" ]; then
      echo "$DEFERRED_EXAMPLES" >&2
    fi
    echo "You have Bash (commands), Read/Grep (investigation), Edit/Write (files), and all other tools available. Execute the steps yourself, verify the results, then report completion." >&2
    record_hook_outcome "no-deferred-actions" "TaskCompleted" "block" "" "" "" "${MODEL_FAMILY:-unknown}"
    return 2
  fi

  return 0
}
