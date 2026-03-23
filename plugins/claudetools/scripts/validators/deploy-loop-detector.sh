#!/bin/bash
# Validator: deploy-test loop detector
# Catches agents repeatedly deploying without fixing the underlying issue.
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Returns: 0 = no issue, 1 = cloudflare propagation note, 2 = deploy loop (block)

DEPLOY_LOG="/tmp/claudetools-deploys-${PPID}.jsonl"

validate_deploy_loop() {
  local COMMAND
  COMMAND=$(hook_get_field '.tool_input.command')

  if [ -z "$COMMAND" ]; then
    return 0
  fi

  # Detect deploy commands
  local IS_DEPLOY=false
  local IS_CLOUDFLARE=false

  case "$COMMAND" in
    *"wrangler deploy"*|*"wrangler publish"*|*"wrangler pages deploy"*|*"npx wrangler deploy"*)
      IS_DEPLOY=true; IS_CLOUDFLARE=true ;;
    *"npm run deploy"*|*"yarn deploy"*|*"pnpm deploy"*)
      IS_DEPLOY=true ;;
    *"vercel deploy"*|*"vercel --prod"*)
      IS_DEPLOY=true ;;
    *"netlify deploy"*)
      IS_DEPLOY=true ;;
    *"fly deploy"*|*"flyctl deploy"*)
      IS_DEPLOY=true ;;
    *"firebase deploy"*)
      IS_DEPLOY=true ;;
  esac

  if [ "$IS_DEPLOY" = false ]; then
    return 0
  fi

  # Record this deploy
  local NOW
  NOW=$(date +%s)
  echo "{\"ts\":${NOW},\"cmd\":\"${COMMAND//\"/\\\"}\"}" >> "$DEPLOY_LOG" 2>/dev/null || true

  # Count deploys in the last 10 minutes (600 seconds)
  local CUTOFF COUNT
  CUTOFF=$((NOW - 600))
  COUNT=0

  if [ -f "$DEPLOY_LOG" ]; then
    while IFS= read -r line; do
      local ts
      ts=$(echo "$line" | jq -r '.ts // 0' 2>/dev/null || echo 0)
      if [ "$ts" -ge "$CUTOFF" ] 2>/dev/null; then
        COUNT=$((COUNT + 1))
      fi
    done < "$DEPLOY_LOG"
  fi

  if [ "$COUNT" -ge 3 ]; then
    echo "DEPLOY LOOP DETECTED: ${COUNT} deploys in the last 10 minutes."
    echo "Stop and diagnose the root cause — repeated deploys rarely fix the problem."
    echo "Check logs, edge cache propagation, or environment config."
    return 2
  fi

  # Cloudflare propagation reminder
  if [ "$IS_CLOUDFLARE" = true ]; then
    echo "Note: Cloudflare edge may take 30-60s to propagate. Wait before testing."
    return 1
  fi

  return 0
}
