#!/usr/bin/env bash
# TaskCompleted hook — verifies the agent actually ran verification commands
# before marking a task complete. Exit 2 to reject, exit 0 to allow.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/worktree.sh"
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || true)

# Check if this is a code project (has package.json, Cargo.toml, go.mod, etc.)
IS_CODE_PROJECT=false
for marker in package.json Cargo.toml go.mod pyproject.toml setup.py Makefile; do
  if [ -f "$CWD/$marker" ]; then
    IS_CODE_PROJECT=true
    break
  fi
done

# Skip non-code projects — no verification needed
if [ "$IS_CODE_PROJECT" = false ]; then
  hook_log "not a code project, skipping"
  exit 0
fi

# Strategy: Check for evidence of verification in multiple places
EVIDENCE_FOUND=0

# 1. Check plugin's own hook log for recent Bash commands that look like verification
LOG_FILE="$(cd "$(dirname "$0")/.." && pwd)/logs/hooks.log"
if [ -f "$LOG_FILE" ]; then
  # Look for recent log entries (last 200 lines) mentioning test/typecheck tools
  RECENT_LOGS=$(tail -200 "$LOG_FILE" 2>/dev/null || true)
  if echo "$RECENT_LOGS" | grep -qiE 'tool=(Bash|bash)' 2>/dev/null; then
    # There were bash invocations — check temp evidence files next
    EVIDENCE_FOUND=$((EVIDENCE_FOUND + 1))
  fi
fi

# 2. Check for test output artifacts that verification commands typically produce
# Vitest/Jest leave coverage dirs, pytest leaves .pytest_cache, etc.
for artifact in \
  "$CWD/coverage" \
  "$CWD/.pytest_cache" \
  "$CWD/target/debug" \
  "$CWD/test-results" \
  "$CWD/.vitest-results"; do
  if [ -d "$artifact" ]; then
    # Check if artifact was modified in the last 30 minutes (recent test run)
    if find "$artifact" -maxdepth 1 -mmin -30 -print -quit 2>/dev/null | grep -q .; then
      EVIDENCE_FOUND=$((EVIDENCE_FOUND + 2))
      break
    fi
  fi
done

# 3. Check shell history for verification commands (most reliable signal)
# Claude Code bash history or system history
VERIFICATION_PATTERNS='npm test|npx tsc|npx vitest|npm run test|npm run typecheck|npm run build|pytest|cargo test|cargo check|go test|make test|jest|mocha|curl .*(localhost|127\.0\.0\.1)|wget .*(localhost|127\.0\.0\.1)'

# Check bash history files
for hist_file in "$HOME/.bash_history" "$HOME/.zsh_history"; do
  if [ -f "$hist_file" ]; then
    # Check last 100 history entries for verification commands
    if tail -100 "$hist_file" 2>/dev/null | grep -qE "$VERIFICATION_PATTERNS"; then
      EVIDENCE_FOUND=$((EVIDENCE_FOUND + 2))
      break
    fi
  fi
done

# 4. Check /tmp for verification breadcrumbs from this session
# Some CI/test tools write temp files
VERIFY_BREADCRUMB=$(session_tmp_path "verification")
if [ -f "$VERIFY_BREADCRUMB" ]; then
  EVIDENCE_FOUND=$((EVIDENCE_FOUND + 3))
fi

# 5. Check if package.json has test/typecheck scripts and if node_modules/.cache
# has recent vitest/tsc entries
if [ -f "$CWD/package.json" ]; then
  HAS_TEST=$(jq -r '.scripts.test // empty' "$CWD/package.json" 2>/dev/null || true)
  HAS_TYPECHECK=$(jq -r '.scripts.typecheck // empty' "$CWD/package.json" 2>/dev/null || true)

  if [ -n "$HAS_TEST" ] || [ -n "$HAS_TYPECHECK" ]; then
    # This project has test/typecheck scripts — evidence bar is higher
    # Check for recent tsc build info
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

  # Suggest project-specific commands
  if [ -f "$CWD/package.json" ]; then
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

  HOOK_DECISION="reject"; HOOK_REASON="no verification evidence"
  exit 2
fi

hook_log "verification evidence score: $EVIDENCE_FOUND"
exit 0
