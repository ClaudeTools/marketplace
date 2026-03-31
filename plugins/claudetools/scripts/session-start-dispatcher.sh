#!/bin/bash
# session-start-dispatcher.sh — Universal SessionStart dispatcher
#
# Replaces 6 individual SessionStart hook entries with a single entry.
# Scripts run sequentially in the order they previously appeared in hooks.json.
# Failures in individual scripts are non-fatal — session startup must not be blocked.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Read stdin once
INPUT=$(cat 2>/dev/null || true)
export INPUT

# Helper: pipe INPUT to a script, suppress failures (session hooks are best-effort)
run_session_hook() {
  local script="$1"
  echo "$INPUT" | bash "$script" || true
}

# Helper: pipe INPUT to a script with an argument (for scripts that take $1 as subcommand)
run_session_hook_with_arg() {
  local script="$1"
  local arg="$2"
  echo "$INPUT" | bash "$script" "$arg" || true
}

# 1. codebase-pilot session index
run_session_hook "$PLUGIN_ROOT/codebase-pilot/scripts/session-index.sh"

# 2. Inject session context into the conversation
run_session_hook "$SCRIPT_DIR/inject-session-context.sh"

# 3. Detect stale documentation
run_session_hook "$SCRIPT_DIR/doc-stale-detector.sh"

# 4. Register this session with the agent mesh
run_session_hook_with_arg "$SCRIPT_DIR/mesh-lifecycle.sh" "register"

# 5. Track worktree session
run_session_hook "$SCRIPT_DIR/track-worktree-session.sh"

# 6. Configure statusline
run_session_hook "$SCRIPT_DIR/statusline/configure.sh"

exit 0
