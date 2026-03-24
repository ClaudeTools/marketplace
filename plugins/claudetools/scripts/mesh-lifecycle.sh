#!/usr/bin/env bash
# mesh-lifecycle.sh — Register/deregister agents in the agent mesh
# Called by hooks.json on SessionStart, WorktreeCreate, SubagentStart (register)
# and SessionEnd, SubagentStop (deregister).
# Always exits 0 — mesh failures must never block sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MESH_CLI="$(dirname "$SCRIPT_DIR")/agent-mesh/cli.js"

source "$SCRIPT_DIR/hook-log.sh"
source "$SCRIPT_DIR/lib/worktree.sh"

ACTION="${1:-}"
INPUT=$(cat 2>/dev/null || true)

if [[ ! -f "$MESH_CLI" ]]; then
  hook_log "mesh-lifecycle: cli.js not found, skipping"
  exit 0
fi

SID=$(get_session_id "$INPUT")

if [[ -z "$SID" ]]; then
  hook_log "mesh-lifecycle: no session_id, skipping"
  exit 0
fi

case "$ACTION" in
  register)
    WT=$(get_worktree_root)
    BR=$(git branch --show-current 2>/dev/null || echo "unknown")
    PID="$PPID"
    AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "main"' 2>/dev/null || echo "main")
    NAME="${AGENT_TYPE}-${SID:0:8}"

    if node "$MESH_CLI" register --id "$SID" --name "$NAME" --worktree "$WT" --branch "$BR" --pid "$PID" 2>&1; then
      hook_log "mesh-lifecycle: registered $NAME (sid=$SID wt=$WT branch=$BR pid=$PID)"
    else
      hook_log "mesh-lifecycle: register failed for $NAME (sid=$SID)"
    fi

    # Collision detection: find other agents on the same worktree with alive PIDs
    MESH_DIR="$(get_repo_root)/.claude/mesh/agents"
    if [[ -d "$MESH_DIR" ]]; then
      for agent_file in "$MESH_DIR"/*.json; do
        [[ -f "$agent_file" ]] || continue
        agent_data=$(jq -r '[.id, .name, .pid, .worktree] | @tsv' "$agent_file" 2>/dev/null) || continue
        IFS=$'\t' read -r a_id a_name a_pid a_wt <<< "$agent_data"
        # Skip self
        [[ "$a_id" == "$SID" ]] && continue
        # Same worktree?
        [[ "$a_wt" == "$WT" ]] || continue
        # PID still alive?
        if kill -0 "$a_pid" 2>/dev/null; then
          echo "[agent-mesh] COLLISION: ${a_name} (PID ${a_pid}) is active on this worktree" >&2
          hook_log "mesh-lifecycle: collision detected — $a_name (PID $a_pid) on $WT"
        fi
      done
    fi

    # Worktree enforcement handled by enforce-worktree-isolation.sh
    ;;

  deregister)
    if node "$MESH_CLI" deregister --id "$SID" 2>&1; then
      hook_log "mesh-lifecycle: deregistered sid=$SID"
    else
      hook_log "mesh-lifecycle: deregister failed for sid=$SID"
    fi
    ;;

  *)
    hook_log "mesh-lifecycle: unknown action '$ACTION' (expected register|deregister)"
    ;;
esac

exit 0
