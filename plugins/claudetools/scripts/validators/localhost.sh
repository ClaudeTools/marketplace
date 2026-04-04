#!/bin/bash
# Validator: localhost URL detection in config files
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: FILE_PATH, BASENAME
# Calls: hook_get_content (lazy NEW_STRING extraction)
# Returns: 0 = clean or not applicable, 1 = localhost found (warning)
# Output: findings written to stdout

validate_localhost() {
  local BASENAME_LOWER
  BASENAME_LOWER=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')

  # --- Allowlist: files where localhost is expected ---
  # Test files may reference localhost for test servers
  is_test_file "$FILE_PATH" && return 0
  # Documentation may reference localhost as examples
  is_doc_file "$FILE_PATH" && return 0
  # Binary/generated files
  is_binary_file "$FILE_PATH" && return 0

  # --- Target: production config files ---
  # Only flag localhost in files that are likely production config
  local IS_PROD_CONFIG=false

  case "$BASENAME_LOWER" in
    wrangler.jsonc|wrangler.json|wrangler.toml)
      IS_PROD_CONFIG=true ;;
    .env.production|.env.prod|.env.staging|.env.deploy)
      IS_PROD_CONFIG=true ;;
    production.json|production.yaml|production.yml|production.toml)
      IS_PROD_CONFIG=true ;;
    vercel.json|netlify.toml|fly.toml|render.yaml|railway.toml)
      IS_PROD_CONFIG=true ;;
    docker-compose.prod.yml|docker-compose.production.yml)
      IS_PROD_CONFIG=true ;;
    cloudflare.json|workers.json)
      IS_PROD_CONFIG=true ;;
  esac

  # Also check path components for production indicators
  case "$FILE_PATH" in
    *config/prod*|*config/production*|*config/staging*|*deploy/*|*infra/*)
      IS_PROD_CONFIG=true ;;
  esac

  # For non-prod-config files, also check generic config files that often contain URLs
  local IS_GENERIC_CONFIG=false
  case "$BASENAME_LOWER" in
    wrangler.jsonc|wrangler.json|wrangler.toml|*.env|.env.*|config.json|config.yaml|config.yml|config.toml|settings.json|settings.yaml)
      IS_GENERIC_CONFIG=true ;;
  esac

  # Skip files that are neither prod config nor generic config
  if [ "$IS_PROD_CONFIG" = "false" ] && [ "$IS_GENERIC_CONFIG" = "false" ]; then
    return 0
  fi

  # Extract the content being written
  local NEW_STRING
  NEW_STRING=$(hook_get_content)

  if [ -z "$NEW_STRING" ]; then
    return 0
  fi

  local ISSUES=""
  local add_issue
  add_issue() { ISSUES="${ISSUES}  - $1\n"; }

  # --- Pattern 1: http://localhost URLs ---
  if echo "$NEW_STRING" | grep -qE 'https?://localhost(:[0-9]+)?(/|"|'"'"'|\s|$)'; then
    add_issue "http(s)://localhost URL detected"
  fi

  # --- Pattern 2: http://127.0.0.1 URLs ---
  if echo "$NEW_STRING" | grep -qE 'https?://127\.0\.0\.1(:[0-9]+)?(/|"|'"'"'|\s|$)'; then
    add_issue "http(s)://127.0.0.1 URL detected"
  fi

  # --- Pattern 3: http://0.0.0.0 URLs ---
  if echo "$NEW_STRING" | grep -qE 'https?://0\.0\.0\.0(:[0-9]+)?(/|"|'"'"'|\s|$)'; then
    add_issue "http(s)://0.0.0.0 URL detected"
  fi

  # --- Pattern 4: Bare localhost:PORT in config values ---
  if echo "$NEW_STRING" | grep -qE '[:=]\s*["\x27]?localhost:[0-9]+'; then
    add_issue "localhost:PORT assignment detected"
  fi

  # --- Pattern 5: ws://localhost WebSocket URLs ---
  if echo "$NEW_STRING" | grep -qE 'wss?://localhost(:[0-9]+)?(/|"|'"'"'|\s|$)'; then
    add_issue "ws(s)://localhost WebSocket URL detected"
  fi

  # --- Filter: skip if localhost appears only in comments ---
  # Simple heuristic: if every localhost line starts with # or //, it's all comments
  if [ -n "$ISSUES" ]; then
    local NON_COMMENT_HITS
    NON_COMMENT_HITS=$(echo "$NEW_STRING" | grep -E '(localhost|127\.0\.0\.1|0\.0\.0\.0)' | grep -cvE '^\s*(#|//)' 2>/dev/null || echo "0")
    if [ "$NON_COMMENT_HITS" -eq 0 ]; then
      # All hits are in comments — allow
      ISSUES=""
    fi
  fi

  # --- Filter: skip if localhost is in an env var reference like process.env.* or ${...} ---
  if [ -n "$ISSUES" ]; then
    # If the ONLY localhost references are inside env-var patterns, skip
    local REAL_HITS
    REAL_HITS=$(echo "$NEW_STRING" | grep -E '(localhost|127\.0\.0\.1|0\.0\.0\.0)' | grep -cvE '(process\.env|os\.environ|\$\{|getenv|ENV\[)' 2>/dev/null || echo "0")
    if [ "$REAL_HITS" -eq 0 ]; then
      ISSUES=""
    fi
  fi

  # --- Emit warning ---
  if [ -n "$ISSUES" ]; then
    local SEVERITY="WARNING"
    [ "$IS_PROD_CONFIG" = "true" ] && SEVERITY="PRODUCTION CONFIG WARNING"

    echo "LOCALHOST URL ${SEVERITY} in ${BASENAME}"
    echo ""
    echo "Localhost URLs will not resolve in deployed environments."
    echo "Detected patterns:"
    echo -e "$ISSUES"
    echo "Replace localhost URLs with production URLs, environment variables,"
    echo "or Cloudflare Workers/Pages-compatible config values."
    return 1
  fi

  return 0
}
