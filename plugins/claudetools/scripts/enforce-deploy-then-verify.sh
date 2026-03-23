#!/bin/bash
# PostToolUse:Bash hook — after deploy commands, warns that endpoint verification is required
# Enforces:
#   - no-shortcuts.md "After deploying: hit the endpoint with real data"
#   - deterministic-over-ai.md "Deployment via CLI"
# Exit 1 = warn (non-blocking), Exit 0 = clean

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the command that just ran
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Detect deploy commands
IS_DEPLOY=false
DEPLOY_TYPE=""

case "$COMMAND" in
  *"wrangler deploy"*|*"wrangler publish"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Cloudflare Workers" ;;
  *"npm run deploy"*|*"yarn deploy"*|*"pnpm deploy"*)
    IS_DEPLOY=true; DEPLOY_TYPE="npm deploy script" ;;
  *"vercel deploy"*|*"vercel --prod"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Vercel" ;;
  *"fly deploy"*|*"flyctl deploy"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Fly.io" ;;
  *"railway up"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Railway" ;;
  *"gh workflow run"*)
    IS_DEPLOY=true; DEPLOY_TYPE="GitHub Actions" ;;
  *"docker push"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Docker" ;;
  *"netlify deploy"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Netlify" ;;
  *"firebase deploy"*)
    IS_DEPLOY=true; DEPLOY_TYPE="Firebase" ;;
  *"aws s3 sync"*|*"aws cloudformation deploy"*|*"aws lambda update"*)
    IS_DEPLOY=true; DEPLOY_TYPE="AWS" ;;
esac

if [ "$IS_DEPLOY" = false ]; then
  record_hook_outcome "enforce-deploy-then-verify" "PostToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
  exit 0
fi

# Check if the deploy command succeeded (tool_response should indicate success)
TOOL_SUCCESS=$(echo "$INPUT" | jq -r '.tool_response.success // "true"' 2>/dev/null || echo "true")
if [ "$TOOL_SUCCESS" = "false" ]; then
  hook_log "deploy command failed, skipping verification reminder"
  exit 0
fi

# Write a breadcrumb so other hooks can check if verification happened
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || true)
BREADCRUMB="/tmp/claude-deploy-pending-${SESSION_ID}"
echo "${DEPLOY_TYPE}|$(date -u +%Y-%m-%dT%H:%M:%SZ)|${COMMAND}" > "$BREADCRUMB" 2>/dev/null || true

record_hook_outcome "enforce-deploy-then-verify" "PostToolUse" "allow" "Bash" "" "" "$MODEL_FAMILY"
exit 0
