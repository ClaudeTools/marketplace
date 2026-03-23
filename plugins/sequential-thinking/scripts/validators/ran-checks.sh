#!/bin/bash
# Validator: verification commands evidence check
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Returns: 0 = evidence found or not a code project, 2 = block (no verification evidence)

validate_ran_checks() {
  # Source worktree lib (safe to re-source due to guard)
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/worktree.sh"

  local CWD
  CWD=$(hook_get_field '.cwd' || true)
  [ -z "$CWD" ] && CWD="."

  # Check if this is a code project (has package.json, Cargo.toml, go.mod, etc.)
  local IS_CODE_PROJECT=false
  for marker in package.json Cargo.toml go.mod pyproject.toml setup.py Makefile; do
    if [ -f "$CWD/$marker" ]; then
      IS_CODE_PROJECT=true
      break
    fi
  done

  # Skip non-code projects — no verification needed
  if [ "$IS_CODE_PROJECT" = false ]; then
    return 0
  fi

  # Strategy: Check for evidence of verification in multiple places
  local EVIDENCE_FOUND=0

  # 1. Check plugin's own hook log for recent Bash commands that look like verification
  local LOG_FILE
  LOG_FILE="$(cd "$(dirname "$0")/.." && pwd)/logs/hooks.log"
  if [ -f "$LOG_FILE" ]; then
    local RECENT_LOGS
    RECENT_LOGS=$(tail -200 "$LOG_FILE" 2>/dev/null || true)
    if echo "$RECENT_LOGS" | grep -qiE 'tool=(Bash|bash)' 2>/dev/null; then
      EVIDENCE_FOUND=$((EVIDENCE_FOUND + 1))
    fi
  fi

  # 2. Check for test output artifacts that verification commands typically produce
  for artifact in \
    "$CWD/coverage" \
    "$CWD/.pytest_cache" \
    "$CWD/target/debug" \
    "$CWD/test-results" \
    "$CWD/.vitest-results"; do
    if [ -d "$artifact" ]; then
      if find "$artifact" -maxdepth 1 -mmin -30 -print -quit 2>/dev/null | grep -q .; then
        EVIDENCE_FOUND=$((EVIDENCE_FOUND + 2))
        break
      fi
    fi
  done

  # 3. Check shell history for verification commands (most reliable signal)
  local VERIFICATION_PATTERNS='npm test|npx tsc|npx vitest|npm run test|npm run typecheck|npm run build|pytest|cargo test|cargo check|go test|make test|jest|mocha|curl .*(localhost|127\.0\.0\.1)|wget .*(localhost|127\.0\.0\.1)'

  for hist_file in "$HOME/.bash_history" "$HOME/.zsh_history"; do
    if [ -f "$hist_file" ]; then
      if tail -100 "$hist_file" 2>/dev/null | grep -qE "$VERIFICATION_PATTERNS"; then
        EVIDENCE_FOUND=$((EVIDENCE_FOUND + 2))
        break
      fi
    fi
  done

  # 4. Check /tmp for verification breadcrumbs from this session
  local VERIFY_BREADCRUMB
  VERIFY_BREADCRUMB=$(session_tmp_path "verification")
  if [ -f "$VERIFY_BREADCRUMB" ]; then
    EVIDENCE_FOUND=$((EVIDENCE_FOUND + 3))
  fi

  # 5. Check if package.json has test/typecheck scripts and if node_modules/.cache
  # has recent vitest/tsc entries
  if [ -f "$CWD/package.json" ]; then
    local HAS_TEST HAS_TYPECHECK
    HAS_TEST=$(jq -r '.scripts.test // empty' "$CWD/package.json" 2>/dev/null || true)
    HAS_TYPECHECK=$(jq -r '.scripts.typecheck // empty' "$CWD/package.json" 2>/dev/null || true)

    if [ -n "$HAS_TEST" ] || [ -n "$HAS_TYPECHECK" ]; then
      if find "$CWD" -name "tsconfig.tsbuildinfo" -mmin -30 -print -quit 2>/dev/null | grep -q .; then
        EVIDENCE_FOUND=$((EVIDENCE_FOUND + 1))
      fi
    fi
  fi

  # Decision: need at least some evidence of verification
  if [ "$EVIDENCE_FOUND" -lt 2 ]; then
    echo "No test or typecheck commands were detected this session." >&2
    echo "Untested changes may introduce regressions that are harder to fix later." >&2
    echo "Run verification commands before completing:" >&2

    if [ -f "$CWD/package.json" ]; then
      local HAS_TEST HAS_TC
      HAS_TEST=$(jq -r '.scripts.test // empty' "$CWD/package.json" 2>/dev/null || true)
      HAS_TC=$(jq -r '.scripts.typecheck // empty' "$CWD/package.json" 2>/dev/null || true)
      [ -n "$HAS_TC" ] && echo "  npm run typecheck" >&2
      [ -n "$HAS_TEST" ] && echo "  npm test" >&2
    elif [ -f "$CWD/Cargo.toml" ]; then
      echo "  cargo check && cargo test" >&2
    elif [ -f "$CWD/go.mod" ]; then
      echo "  go vet ./... && go test ./..." >&2
    elif [ -f "$CWD/pyproject.toml" ] || [ -f "$CWD/setup.py" ]; then
      echo "  pytest" >&2
    else
      echo "  Run your project's test suite" >&2
    fi

    return 2
  fi

  return 0
}
