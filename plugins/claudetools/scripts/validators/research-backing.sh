#!/bin/bash
# Validator: research-backing-gate
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, FILE_PATH
# Calls: hook_get_content (lazy new_string/content extraction)
# Returns: 0 = no external patterns or research done, 2 = external code without research (block)
# Output: block message written to stdout

validate_research_backing() {
  local CONTENT
  CONTENT=$(hook_get_content)
  [ -z "$CONTENT" ] && return 0

  # --- Skip non-code files and test files ---
  case "$FILE_PATH" in
    *.test.*|*.spec.*|*__tests__*|*__mocks__*|*fixtures*) return 0 ;;
    *.md|*.json|*.yaml|*.yml|*.toml|*.lock|*.css|*.svg|*.sh) return 0 ;;
    *.config.*|*.rc|*CLAUDE.md) return 0 ;;
  esac

  # --- Pattern 1: External HTTP calls ---
  local EXTERNAL_URL=0
  if echo "$CONTENT" | grep -qE "fetch\s*\(\s*['\"\`]https?://" 2>/dev/null; then
    # Check it's not localhost or internal
    if ! echo "$CONTENT" | grep -qE "fetch\s*\(\s*['\"\`]https?://(localhost|127\.0\.0\.1|0\.0\.0\.0)" 2>/dev/null; then
      EXTERNAL_URL=1
    fi
  fi
  # axios/http client calls to external URLs
  if echo "$CONTENT" | grep -qE "(axios\.(get|post|put|delete|patch)|http\.(get|post)|request\()\s*\(\s*['\"\`]https?://" 2>/dev/null; then
    EXTERNAL_URL=1
  fi

  # --- Pattern 2: Known third-party SDK imports ---
  local SDK_IMPORT=0
  if echo "$CONTENT" | grep -qE "from\s+['\"](@?stripe|aws-sdk|@aws-sdk|@google-cloud|firebase|twilio|sendgrid|@sendgrid|@slack|braintree|paypal|@paypal|shopify|@shopify)" 2>/dev/null; then
    SDK_IMPORT=1
  fi
  # Python SDK imports
  if echo "$CONTENT" | grep -qE "^(import|from)\s+(boto3|stripe|twilio|sendgrid|google\.cloud|firebase_admin|slack_sdk)" 2>/dev/null; then
    SDK_IMPORT=1
  fi

  # --- Pattern 3: SDK constructors ---
  local CONSTRUCTOR=0
  if echo "$CONTENT" | grep -qE "new\s+(Stripe|S3Client|DynamoDBClient|CloudFrontClient|SESClient|SNSClient|SQSClient|FirebaseApp|Twilio)\s*\(" 2>/dev/null; then
    CONSTRUCTOR=1
  fi

  # --- Pattern 4: OAuth/auth token patterns ---
  local OAUTH=0
  if echo "$CONTENT" | grep -qE "(oauth|OAuth|getAccessToken|exchangeCode|authorizationUrl|tokenEndpoint|client_credentials|authorization_code)\b" 2>/dev/null; then
    OAUTH=1
  fi

  # --- Fast exit: no external patterns detected → allow immediately ---
  if [ "$EXTERNAL_URL" -eq 0 ] && [ "$SDK_IMPORT" -eq 0 ] && [ "$CONSTRUCTOR" -eq 0 ] && [ "$OAUTH" -eq 0 ]; then
    return 0
  fi

  # --- External pattern detected — check for research signals ---
  # Look for evidence that the agent did research before this write
  local TRANSCRIPT
  TRANSCRIPT=$(hook_get_field '.transcript' 2>/dev/null || true)

  local RESEARCH_DONE=0
  if [ -n "$TRANSCRIPT" ]; then
    if echo "$TRANSCRIPT" | grep -qiE "(WebSearch|WebFetch|searched.*docs|verified.*documentation|checked.*api|read.*docs|context7)" 2>/dev/null; then
      RESEARCH_DONE=1
    fi
  fi

  # If no transcript available, check session hook logs for recent WebSearch/WebFetch
  if [ "$RESEARCH_DONE" -eq 0 ]; then
    local LOG_FILE="${CLAUDE_PLUGIN_ROOT:-}/logs/hooks.log"
    if [ -f "$LOG_FILE" ]; then
      # Look for WebSearch/WebFetch in last 20 log entries
      local RECENT_RESEARCH
      RECENT_RESEARCH=$(tail -20 "$LOG_FILE" 2>/dev/null | grep -ci 'WebSearch\|WebFetch' || echo 0)
      if [ "$RECENT_RESEARCH" -gt 0 ]; then
        RESEARCH_DONE=1
      fi
    fi
  fi

  # --- If external patterns found and no research evidence → block ---
  if [ "$RESEARCH_DONE" -eq 0 ]; then
    local DETECTED=""
    [ "$EXTERNAL_URL" -eq 1 ] && DETECTED="${DETECTED}external API URL, "
    [ "$SDK_IMPORT" -eq 1 ] && DETECTED="${DETECTED}third-party SDK import, "
    [ "$CONSTRUCTOR" -eq 1 ] && DETECTED="${DETECTED}SDK constructor, "
    [ "$OAUTH" -eq 1 ] && DETECTED="${DETECTED}OAuth/auth pattern, "
    DETECTED=${DETECTED%, }

    local REASON="Detected ${DETECTED} in code without prior research. Search current docs for the service/API before writing this code — never assume API formats from training data. Use WebSearch or WebFetch to verify current API shapes."
    echo "$REASON"
    return 2
  fi

  # Research was done — allow
  return 0
}
