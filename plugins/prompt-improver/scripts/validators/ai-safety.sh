#!/bin/bash
# Validator: ai-safety-check
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Calls: hook_get_field for command extraction
# Returns: 0 = safe or degraded gracefully, 2 = AI flagged unsafe (block)
# Output: block message written to stdout
# Note: Degrades gracefully if claude CLI is missing or times out.

validate_ai_safety() {
  local CMD
  CMD=$(hook_get_field '.tool_input.command')

  if [ -z "$CMD" ]; then
    return 0
  fi

  # --- Fast path: regex pre-filter ---
  # Only invoke AI for commands that match known destructive patterns.
  # All other commands exit immediately (zero overhead).
  if ! echo "$CMD" | grep -qE '(\brm\b|\brmdir\b|git\s+(checkout|reset|rebase|stash|branch\s+-D)|docker\s+(prune|rm\b)|DROP\s+TABLE|DELETE\s+FROM|\bkill\b|\bpkill\b|\bdd\b|\bmkfs\b|>\s*/dev/)'; then
    return 0
  fi

  # --- Slow path: AI evaluation ---
  # Command matched a destructive pattern — ask AI to evaluate safety

  # Check if claude CLI is available
  if ! command -v claude &>/dev/null; then
    hook_log "claude CLI not available, allowing"
    return 0
  fi

  local PROMPT="You are a command safety evaluator.

<command_to_evaluate>
${CMD}
</command_to_evaluate>

<safety_rules>
1. Prefer safer alternatives:
   - git checkout . → use git stash instead
   - rm -rf → rebuild from source instead
2. Investigate before deleting (ls/find before rm, git log before reset)
3. When in doubt, ask the user rather than allowing a destructive operation
</safety_rules>

<examples>
Command: rm /tmp/build.log → SAFE (targeted temp file removal)
Command: rm -rf ~/projects → UNSAFE (destroys entire projects directory)
Command: git checkout src/main.ts → SAFE (restores a single specific file)
Command: git checkout . → UNSAFE (discards all uncommitted changes across entire repo)
</examples>

CRITICAL: False UNSAFE blocks waste developer time and break flow. Only flag UNSAFE when destructive scope is clearly visible in the command.

<output_format>
Respond with EXACTLY one word on the first line:
- SAFE — if the command is reasonable and targeted (e.g., rm of a specific temp file, git checkout of a single file)
- UNSAFE — if the command is broadly destructive, irreversible, or affects critical data without a clear safe target

If you cannot determine safety with confidence, respond SAFE — do not guess UNSAFE.

Then on the second line, a brief reason (10 words max).
</output_format>"

  local RESULT
  RESULT=$(echo "$PROMPT" | timeout 10 claude -p --no-input --model haiku 2>/dev/null || echo "TIMEOUT")

  # Degrade gracefully on timeout or CLI error
  case "$RESULT" in
    TIMEOUT|"")
      hook_log "AI safety check timed out or failed, allowing"
      return 0
      ;;
  esac

  local VERDICT REASON
  VERDICT=$(echo "$RESULT" | head -1 | tr -d '[:space:]')
  REASON=$(echo "$RESULT" | sed -n '2p' | head -c 100)

  case "$VERDICT" in
    SAFE)
      hook_log "AI safety: SAFE — $REASON"
      return 0
      ;;
    UNSAFE)
      hook_log "AI safety: UNSAFE — $REASON"
      local MSG="AI safety check: ${REASON:-Command flagged as potentially destructive. Use a safer alternative or confirm with the user.}"
      echo "$MSG"
      return 2
      ;;
    *)
      # Unexpected response — allow (degrade gracefully)
      hook_log "AI safety: unexpected verdict '$VERDICT', allowing"
      return 0
      ;;
  esac
}
