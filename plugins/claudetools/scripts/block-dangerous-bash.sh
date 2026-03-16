#!/bin/bash
# PreToolUse hook for Bash — blocks known dangerous patterns
# Outputs JSON with permissionDecision "block" to deny. Exit 0 always.

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$CMD" ]; then
  exit 0
fi

BLOCKED=""

# --- Destructive filesystem operations ---
# rm -rf with broad paths (/, ~, $HOME, ../) or --no-preserve-root
if echo "$CMD" | grep -qE 'rm\s+-rf\s+(/|~|\$HOME|\.\./)|--no-preserve-root'; then
  BLOCKED="Blocked: rm -rf on broad path"
fi

# chmod 777 (world-writable permissions), including with -R flag
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'chmod\s+(-[a-zA-Z]+\s+)*777'; then
  BLOCKED="Blocked: chmod 777 (world-writable permissions)"
fi

# --- Destructive git operations ---
# git reset --hard
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+reset\s+--hard'; then
  BLOCKED="Blocked: git reset --hard (destructive, may lose work)"
fi

# git push --force/-f to main/master
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+push\s+.*(--force|-f).*(main|master)'; then
  BLOCKED="Blocked: force push to main/master"
fi

# git clean -f (deletes untracked files)
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  BLOCKED="Blocked: git clean -f (deletes untracked files)"
fi

# git add -A / git add . (force explicit file staging)
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+add\s+(-A|--all|\.\s*$|\.\s+)'; then
  BLOCKED="Blocked: git add -A/. (stage specific files to avoid accidental secret commits)"
fi

# git add of secrets (.env*, *.pem, *.key, *credentials*)
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'git\s+add\s+.*(\.(env|pem|key)|credentials)'; then
  BLOCKED="Blocked: git add of sensitive file (.env/.pem/.key/credentials)"
fi

# --- Supply chain / network risks ---
# curl/wget piped to sh/bash
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(curl|wget).*\|\s*(ba)?sh'; then
  BLOCKED="Blocked: curl/wget piped to shell (supply chain risk)"
fi

# npm publish / pip upload (accidental package publishing)
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(npm\s+publish|pip\s+upload|twine\s+upload|yarn\s+publish)'; then
  BLOCKED="Blocked: package publish/upload (accidental publishing risk)"
fi

# --- Secret leakage ---
# cat/echo/print of .env files piped to other commands
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(cat|echo|printf|print)\s+.*\.env.*\|'; then
  BLOCKED="Blocked: .env content piped to another command (secret leakage risk)"
fi

# --- Container security ---
# docker run --privileged (container escape risk)
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'docker\s+run\s+.*--privileged'; then
  BLOCKED="Blocked: docker run --privileged (container escape risk)"
fi

# --- Bulk file deletion via find ---
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'find\s.*(-delete|--delete)'; then
  BLOCKED="Blocked: find -delete (bulk file deletion)"
fi

# dd writing to device
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '\bdd\s+.*of=/dev/'; then
  BLOCKED="Blocked: dd writing to device"
fi

# --- Disk/filesystem destruction ---
# mkfs, fdisk, wipefs, parted on devices
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '\b(mkfs|fdisk|wipefs|parted)\b.*(/dev/|/disk)'; then
  BLOCKED="Blocked: disk/filesystem destruction command"
fi

# --- Reverse shells ---
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '/dev/tcp/|nc\s+.*-e\s|ncat\s+.*-e\s'; then
  BLOCKED="Blocked: reverse shell pattern detected"
fi
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE "python[23]?\s+-c\s+.*socket.*subprocess|perl\s+-e\s+.*socket.*exec"; then
  BLOCKED="Blocked: reverse shell pattern detected"
fi

# --- Environment destruction ---
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'export\s+PATH\s*=\s*""'; then
  BLOCKED="Blocked: clearing PATH (environment destruction)"
fi

# --- Deploy without typecheck gate ---
# Block deploy commands that aren't preceded by typecheck in the same chain
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(npm\s+run\s+deploy|wrangler\s+deploy|vercel\s+deploy|netlify\s+deploy)'; then
  # Allow if typecheck is in the same command chain (&&)
  if ! echo "$CMD" | grep -qE '(tsc|typecheck|type-check).*&&.*(deploy)'; then
    BLOCKED="Blocked: deploy without typecheck. Run typecheck first: npm run typecheck && npm run deploy"
  fi
fi

# --- Hallucinated package detection ---
# Flag packages with 5+ hyphenated segments (likely hallucinated)
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE '(npm|pnpm|yarn)\s+(install|add)\s+(@[a-z0-9-]+/)?[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+'; then
  BLOCKED="Warning: Package name looks hallucinated (too many hyphenated segments) — verify it exists"
fi
# Flag pip install of suspiciously long package names
if [ -z "$BLOCKED" ] && echo "$CMD" | grep -qE 'pip3?\s+install\s+[a-z]+-[a-z]+-[a-z]+-[a-z]+-[a-z]+'; then
  BLOCKED="Warning: pip package name looks hallucinated — verify it exists on PyPI"
fi

if [ -n "$BLOCKED" ]; then
  HOOK_DECISION="block" HOOK_REASON="$BLOCKED"
  record_hook_outcome "block-dangerous-bash" "PreToolUse" "block" "Bash" "" "" "$MODEL_FAMILY"
  jq -n \
    --arg reason "$BLOCKED" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "block",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

record_hook_outcome "block-dangerous-bash" "PreToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
exit 0
