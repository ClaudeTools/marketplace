#!/bin/bash
# Validator: AI-assisted semantic audit of agent output
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = clean or skipped, 1 = semantic issues found (warning)

validate_semantic_agent() {
  local CWD
  CWD=$(hook_get_field '.cwd' || echo ".")
  [ -z "$CWD" ] && CWD="."

  # Only run in git repos
  git -C "$CWD" rev-parse --is-inside-work-tree 2>/dev/null || return 0

  # Get the diff — only audit if substantial changes
  local DIFF
  DIFF=$(git -C "$CWD" diff 2>/dev/null || true)
  local DIFF_LINES
  DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

  # Skip if fewer than 50 lines changed (not worth an audit)
  [ "$DIFF_LINES" -lt 50 ] && return 0

  # Get changed file list for context
  local CHANGED_FILES
  CHANGED_FILES=$(git -C "$CWD" diff --name-only 2>/dev/null | head -20)

  # Build the audit prompt — deterministic (no AI in the prompt construction)
  local AUDIT_PROMPT="You are a code quality auditor. Review this git diff for SEMANTIC violations only.

Deterministic checks (grep-based) already caught: TODOs, stubs, empty functions, type abuse.
Do NOT re-report those. Focus ONLY on what grep cannot detect:

1. SCOPE: Were files modified that seem unrelated to the task? List them.
2. COMPLETENESS: Does the diff look like a partial implementation? (e.g., API endpoint with no error handling, UI component with no loading/error states, database query with no input validation)
3. SHORTCUTS: Are there functions that return plausible-looking but hardcoded/fake data? Constants that should be dynamic? Logic that looks copy-pasted without adaptation?
4. VERIFICATION: If tests were added, do they test real behavior or just assert that functions exist?
5. DEPENDENCIES: Were new packages added without clear justification visible in the diff?

Changed files:
${CHANGED_FILES}

Respond with ONLY a bulleted list of findings, or 'CLEAN' if no semantic issues found.
Keep response under 10 lines. No preamble."

  # Run the audit via Claude CLI in non-interactive mode
  # Timeout after 30 seconds — this is a quick check, not a deep review
  local AUDIT_RESULT
  AUDIT_RESULT=$(echo "$DIFF" | timeout 30 claude -p "$AUDIT_PROMPT" --no-input --model haiku 2>/dev/null || echo "AUDIT_SKIPPED")

  # If audit was skipped (timeout, CLI not available, etc.), allow silently
  [ "$AUDIT_RESULT" = "AUDIT_SKIPPED" ] && return 0

  # If clean, allow silently
  echo "$AUDIT_RESULT" | grep -qi "^CLEAN$" && return 0

  # Report semantic findings as a warning
  echo "SEMANTIC AUDIT (AI-assisted review of ${DIFF_LINES}-line diff):"
  echo "$AUDIT_RESULT"
  echo ""
  echo "These are AI observations — verify before acting. Deterministic checks already passed."
  return 1
}
