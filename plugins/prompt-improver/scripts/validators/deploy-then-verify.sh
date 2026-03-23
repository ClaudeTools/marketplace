#!/bin/bash
# Validator: deploy command detection + breadcrumb writing
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Returns: 0 = no deploy detected or deploy failed, 1 = deploy succeeded (warn)

validate_deploy_then_verify() {
  # Extract the command that just ran
  local COMMAND
  COMMAND=$(hook_get_field '.tool_input.command')

  if [ -z "$COMMAND" ]; then
    return 0
  fi

  # Detect deploy commands
  local IS_DEPLOY=false
  local DEPLOY_TYPE=""

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
    return 0
  fi

  # Check if the deploy command succeeded (tool_response should indicate success)
  local TOOL_SUCCESS
  TOOL_SUCCESS=$(hook_get_field '.tool_response.success' || echo "true")
  [ -z "$TOOL_SUCCESS" ] && TOOL_SUCCESS="true"
  if [ "$TOOL_SUCCESS" = "false" ]; then
    return 0
  fi

  # Write a breadcrumb so other hooks can check if verification happened
  local SESSION_ID
  SESSION_ID=$(hook_get_field '.session_id' || echo "unknown")
  local BREADCRUMB="/tmp/claude-deploy-pending-${SESSION_ID}"
  echo "${DEPLOY_TYPE}|$(date -u +%Y-%m-%dT%H:%M:%SZ)|${COMMAND}" > "$BREADCRUMB" 2>/dev/null || true

  echo "Deploy completed (${DEPLOY_TYPE}). Verify it works before continuing:"
  echo "  1. curl the deployed endpoint with real data"
  echo "  2. Check the response for correctness"
  echo "  3. If UI changes: open in Chrome and verify visually"
  echo ""
  echo "Unverified deploys waste debugging time later."
  record_hook_outcome "enforce-deploy-then-verify" "PostToolUse" "warn" "Bash" "" "" "$MODEL_FAMILY"
  return 1
}
