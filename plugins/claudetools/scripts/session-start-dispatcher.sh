#!/bin/bash
# session-start-dispatcher.sh — Universal SessionStart dispatcher
#
# Replaces 5 individual SessionStart hook entries with a single entry.
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

# 0a. Install skills as user-level symlinks (unprefixed names)
run_session_hook "$SCRIPT_DIR/install-skills.sh"

# 0b. Ensure srcpilot is installed (one-time, marker-gated)
run_session_hook "$SCRIPT_DIR/ensure-srcpilot.sh"

# 1. srcpilot session index
run_session_hook "$SCRIPT_DIR/session-index.sh"

# 2. Inject session context into the conversation
run_session_hook "$SCRIPT_DIR/inject-session-context.sh"

# 3. Detect stale documentation
run_session_hook "$SCRIPT_DIR/doc-stale-detector.sh"

# 4. Configure statusline
run_session_hook "$SCRIPT_DIR/statusline/configure.sh"

exit 0
