#!/bin/bash
# PreToolUse hook for Read|Edit|Write — blocks access to sensitive files
# Matches: .env files, private keys, SSH keys, credentials, secrets, wallets
# Allows: .env.example, .env.template

set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/ensure-db.sh"
ensure_metrics_db 2>/dev/null || true
source "$(dirname "$0")/lib/adaptive-weights.sh"
MODEL_FAMILY=$(detect_model_family)
hook_log "invoked"
trap 'hook_log_result $? "${HOOK_DECISION:-allow}" "${HOOK_REASON:-}"' EXIT
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
BASENAME_LOWER=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]')
BLOCKED=""

# Allowlist — exit early for documentation files
case "$BASENAME" in
  .env.example|.env.template) exit 0 ;;
esac

# .env files (.env, .env.local, .env.production, etc.)
# Allow reading .env for debugging; block writes to prevent accidental secret modification
if echo "$BASENAME" | grep -qE '^\.env($|\..*)'; then
  if [ "$TOOL_NAME" = "Read" ]; then
    exit 0  # Reading .env for debugging is safe
  fi
  BLOCKED="Cannot write to .env file '${BASENAME}'. Environment files contain secrets (API keys, database passwords) that must be edited manually by the user. To inspect its contents, use the Read tool instead."
fi

# TLS/SSL private keys: *.pem, *.key, *.p12, *.pfx
if [ -z "$BLOCKED" ]; then
  case "$BASENAME_LOWER" in
    *.pem|*.key|*.p12|*.pfx)
      BLOCKED="Cannot access private key file '${BASENAME}'. TLS/SSL private keys (.pem, .key, .p12, .pfx) contain cryptographic material that should never be read or modified by automated tools. Manage certificates manually or through a secrets manager." ;;
  esac
fi

# SSH keys: id_rsa, id_ed25519, id_ecdsa (and .pub variants)
if [ -z "$BLOCKED" ] && echo "$FILE_PATH" | grep -qE '\.ssh/(id_rsa|id_ed25519|id_ecdsa)(\.pub)?$'; then
  BLOCKED="Cannot access SSH key file '${BASENAME}'. SSH keys are authentication credentials — modifying them could lock you out of remote systems. Manage SSH keys manually with ssh-keygen."
fi

# Basenames containing: credentials, secret, token (case-insensitive)
if [ -z "$BLOCKED" ] && echo "$BASENAME_LOWER" | grep -qE '(credentials|secret|token)'; then
  BLOCKED="Cannot access '${BASENAME}' — the filename contains 'credentials', 'secret', or 'token', indicating it holds sensitive data. If this file is safe to access (e.g., a type definition or config schema), rename it to avoid these keywords."
fi

# Wallet files: wallet.dat, *.keystore
if [ -z "$BLOCKED" ]; then
  case "$BASENAME_LOWER" in
    wallet.dat|*.keystore)
      BLOCKED="Cannot access wallet/keystore file '${BASENAME}'. These files contain cryptographic keys for wallets or app signing. Manage them manually or through your platform's key management." ;;
  esac
fi

# AWS credentials path
if [ -z "$BLOCKED" ] && echo "$FILE_PATH" | grep -qE '\.aws/credentials$'; then
  BLOCKED="Cannot access AWS credentials file (~/.aws/credentials). This file contains your AWS access keys. Configure AWS credentials manually with 'aws configure' or use environment variables."
fi

# GCloud credentials path
if [ -z "$BLOCKED" ] && echo "$FILE_PATH" | grep -qE '\.config/gcloud/credentials\.db$'; then
  BLOCKED="Cannot access GCloud credentials database. This file stores your Google Cloud authentication tokens. Use 'gcloud auth login' to manage credentials."
fi

# Output blocking JSON if matched
if [ -n "$BLOCKED" ]; then
  HOOK_DECISION="block" HOOK_REASON="$BLOCKED"
  record_hook_outcome "guard-sensitive-files" "PreToolUse" "block" "$TOOL_NAME" "" "" "$MODEL_FAMILY"
  jq -n --arg reason "$BLOCKED" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":$reason}}'
  exit 0
fi

record_hook_outcome "guard-sensitive-files" "PreToolUse" "allow" "$TOOL_NAME" "" "" "$MODEL_FAMILY"
exit 0
