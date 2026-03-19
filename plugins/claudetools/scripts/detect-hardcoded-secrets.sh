#!/bin/bash
# PostToolUse:Edit|Write hook — warns when hardcoded secrets/credentials are written into code
# Enforces: feedback_no_hardcode.md "Always use env vars, globals, or config files"
# Exit 1 = warn (non-blocking), Exit 0 = clean

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT

# Extract the file path that was just written/edited
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || true)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# --- Allowlist: files where secrets/keys are expected ---
case "$FILE_PATH" in
  *.env|*.env.*|.env.example|.env.local|.env.template)
    # .env files ARE the correct place for secrets
    exit 0
    ;;
  *.test.*|*.spec.*|*__tests__*|*__mocks__*|*fixtures*|*__fixtures__*)
    # Test files may have fake keys for testing
    exit 0
    ;;
  *.md|*.txt|*.rst|*.adoc)
    # Documentation may reference key formats
    exit 0
    ;;
  *.lock|*.sum|*.svg|*.png|*.jpg|*.gif|*.ico|*.woff*|*.ttf|*.eot)
    # Binary/generated files
    exit 0
    ;;
  *secret*template*|*secret*example*|*credential*example*)
    # Template files showing the expected format
    exit 0
    ;;
esac

# Extract the content being written
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty' 2>/dev/null || true)

if [ -z "$NEW_STRING" ]; then
  exit 0
fi

ISSUES=""
add_issue() { ISSUES="${ISSUES}  - $1\n"; }

SQ="'"  # single-quote variable for safe embedding in patterns

# --- Pattern 1: AWS Access Keys (AKIA...) ---
if echo "$NEW_STRING" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  add_issue "AWS Access Key ID detected (AKIA...)"
fi

# --- Pattern 2: AWS Secret Keys (40-char base64 near aws/secret/key context) ---
if echo "$NEW_STRING" | grep -qE "[${SQ}\"][A-Za-z0-9/+=]{40}[${SQ}\"]" && \
   echo "$NEW_STRING" | grep -qiE '(aws|secret|key)'; then
  add_issue "Possible AWS Secret Access Key (40-char string near aws/secret/key context)"
fi

# --- Pattern 3: Generic API key assignments ---
# Matches: api_key = "...", apiKey: "...", API_KEY = "sk-..." etc.
if echo "$NEW_STRING" | grep -qiE "(api[_-]?key|apikey|api[_-]?secret)[[:space:]]*[:=][[:space:]]*[\"${SQ}][A-Za-z0-9_.+=/-]{8,}[\"${SQ}]"; then
  add_issue "Hardcoded API key assignment detected"
fi

# --- Pattern 4: Generic password/secret assignments ---
if echo "$NEW_STRING" | grep -qiE "(password|passwd|pwd|secret|token|credential)[[:space:]]*[:=][[:space:]]*[\"${SQ}][^[:space:]\"${SQ}]{8,}[\"${SQ}]"; then
  # Exclude common false positives: placeholder values, env var references, type annotations
  MATCH=$(echo "$NEW_STRING" | grep -iE "(password|passwd|pwd|secret|token|credential)[[:space:]]*[:=][[:space:]]*[\"${SQ}][^[:space:]\"${SQ}]{8,}[\"${SQ}]" | head -1)
  # Allow: process.env.*, os.environ.*, env("..."), ${...}, ENV["..."], placeholder patterns
  if ! echo "$MATCH" | grep -qE '(process\.env|os\.environ|env\(|getenv|\$\{|ENV\[|placeholder|example|changeme|your[_-]|<[^>]+>|\*{3,})'; then
    add_issue "Hardcoded password/secret/token assignment detected"
  fi
fi

# --- Pattern 5: Private keys ---
if echo "$NEW_STRING" | grep -qE 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY'; then
  add_issue "Private key material detected"
fi

# --- Pattern 6: GitHub tokens ---
if echo "$NEW_STRING" | grep -qE '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36,}'; then
  add_issue "GitHub personal access token detected"
fi

# --- Pattern 7: Slack tokens ---
if echo "$NEW_STRING" | grep -qE 'xox[baprs]-[A-Za-z0-9-]{10,}'; then
  add_issue "Slack token detected"
fi

# --- Pattern 8: Stripe keys ---
if echo "$NEW_STRING" | grep -qE '(sk|pk|rk)_(live|test)_[A-Za-z0-9]{20,}'; then
  add_issue "Stripe API key detected"
fi

# --- Pattern 9: OpenAI / Anthropic keys ---
if echo "$NEW_STRING" | grep -qE 'sk-[A-Za-z0-9]{20,}'; then
  # Exclude if it looks like a variable reference or env var
  MATCH=$(echo "$NEW_STRING" | grep -E 'sk-[A-Za-z0-9]{20,}' | head -1)
  if ! echo "$MATCH" | grep -qE '(process\.env|os\.environ|env\(|getenv|\$\{|ENV\[)'; then
    add_issue "OpenAI/Anthropic-style API key detected (sk-...)"
  fi
fi

# --- Pattern 10: Generic bearer tokens ---
if echo "$NEW_STRING" | grep -qE 'Bearer[[:space:]]+[A-Za-z0-9_.+=/:-]{20,}'; then
  MATCH=$(echo "$NEW_STRING" | grep -E 'Bearer[[:space:]]+[A-Za-z0-9_.+=/:-]{20,}' | head -1)
  if ! echo "$MATCH" | grep -qE '(\$\{|process\.env|os\.environ|getenv|ENV\[|<[^>]+>|\{[^}]+\})'; then
    add_issue "Hardcoded Bearer token detected"
  fi
fi

# --- Pattern 11: Connection strings with embedded passwords ---
if echo "$NEW_STRING" | grep -qE '(mysql|postgres|mongodb|redis|amqp)://[^:]+:[^@]{8,}@'; then
  MATCH=$(echo "$NEW_STRING" | grep -E '(mysql|postgres|mongodb|redis|amqp)://[^:]+:[^@]{8,}@' | head -1)
  if ! echo "$MATCH" | grep -qE '(\$\{|process\.env|os\.environ|getenv|ENV\[|<[^>]+>|\{[^}]+\}|placeholder|example|changeme)'; then
    add_issue "Database connection string with embedded password detected"
  fi
fi

# --- Pattern 12: Google/GCP/Firebase keys ---
if echo "$NEW_STRING" | grep -qE 'AIza[0-9A-Za-z_-]{35}'; then
  add_issue "Google API key detected (AIza...)"
fi

# --- Emit warning if any issues found ---
if [ -n "$ISSUES" ]; then
  BASENAME=$(basename "$FILE_PATH")
  HOOK_DECISION="warn" HOOK_REASON="hardcoded secrets in $BASENAME"

  echo "HARDCODED SECRET WARNING in ${BASENAME}"
  echo ""
  echo "Secrets and credentials must never be hardcoded in source files."
  echo "Detected patterns:"
  echo -e "$ISSUES"
  echo "Use environment variables (process.env.*, os.environ[*]) or a config"
  echo "system (.env files, vault, SSM) instead of embedding credentials in code."
  record_hook_outcome "detect-hardcoded-secrets" "PostToolUse" "warn" "" "" "" "$MODEL_FAMILY"
  exit 1
fi

record_hook_outcome "detect-hardcoded-secrets" "PostToolUse" "allow" "" "" "" "$MODEL_FAMILY"
exit 0
