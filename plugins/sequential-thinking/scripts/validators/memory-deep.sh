#!/usr/bin/env bash
# Validator: deep memory extraction via Haiku API
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT
# Calls: hook_log
# Returns: 0 always (side-effect runner)

run_memory_deep() {
  # Require API key — silently skip if not available
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    hook_log "memory-extract-deep: no ANTHROPIC_API_KEY, skipping LLM analysis"
    return 0
  fi

  # Require curl
  if ! command -v curl &>/dev/null; then
    hook_log "memory-extract-deep: curl not found, skipping"
    return 0
  fi

  local PLUGIN_DATA="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/data"
  mkdir -p "$PLUGIN_DATA" 2>/dev/null || true
  local CANDIDATES_FILE="$PLUGIN_DATA/memory-candidates.jsonl"

  local SESSION_ID
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
  local TRANSCRIPT
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)
  local TIMESTAMP
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
    hook_log "memory-extract-deep: no transcript found"
    return 0
  fi

  hook_log "memory-extract-deep: analyzing transcript with Haiku"

  # Build a condensed session summary from the transcript (~2000 tokens max)
  # Extract: tool calls, errors, user messages, key decisions
  local SUMMARY
  SUMMARY=$(jq -r '
    if .role == "human" or .role == "user" then
      "USER: " + (
        if (.content | type) == "array" then
          [.content[] | select(type == "string" or .type == "text") |
           if type == "string" then . else .text end] | join(" ")
        else (.content // "") end
      ) | .[0:300]
    elif .role == "assistant" then
      .content // [] |
      if type == "array" then
        [.[] | select(.type == "tool_use") |
         "TOOL: " + .name + "(" + ((.input | keys | join(",")) // "") + ")"] | join("\n")
      else empty end
    else empty end
  ' "$TRANSCRIPT" 2>/dev/null | tail -80 | head -c 6000 || true)

  if [[ -z "$SUMMARY" || ${#SUMMARY} -lt 50 ]]; then
    hook_log "memory-extract-deep: transcript too short for analysis"
    return 0
  fi

  # Escape the summary for JSON
  local ESCAPED_SUMMARY
  ESCAPED_SUMMARY=$(printf '%s' "$SUMMARY" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || \
    printf '%s' "$SUMMARY" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' '\\' | sed 's/\\/\\n/g')

  # Call Haiku API
  local RESPONSE
  RESPONSE=$(curl -s --max-time 30 \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    "https://api.anthropic.com/v1/messages" \
    -d "{
      \"model\": \"claude-haiku-4-5-20251001\",
      \"max_tokens\": 512,
      \"messages\": [{
        \"role\": \"user\",
        \"content\": \"Analyze this Claude Code session transcript excerpt. Extract observations worth remembering for future sessions. Categories:\\n- feedback: user corrections or preferences\\n- reference: important file/API/service locations\\n- project: decisions, constraints, or context\\n- pattern: recurring approaches or anti-patterns\\n\\nOutput ONLY a JSON array: [{\\\"type\\\": \\\"...\\\", \\\"description\\\": \\\"...\\\", \\\"confidence\\\": 0.0-1.0}]\\nKeep only high-value observations (max 5). Skip trivial or obvious items.\\n\\nTranscript:\\n${ESCAPED_SUMMARY}\"
      }]
    }" 2>/dev/null || true)

  if [[ -z "$RESPONSE" ]]; then
    hook_log "memory-extract-deep: API call failed or timed out"
    return 0
  fi

  # Extract the text content from Haiku's response
  local ANALYSIS
  ANALYSIS=$(echo "$RESPONSE" | jq -r '.content[0].text // ""' 2>/dev/null || true)

  if [[ -z "$ANALYSIS" ]]; then
    hook_log "memory-extract-deep: empty response from Haiku"
    return 0
  fi

  # Parse JSON array from response and write candidates
  echo "$ANALYSIS" | jq -c '.[]' 2>/dev/null | while IFS= read -r item; do
    local TYPE DESC CONF
    TYPE=$(echo "$item" | jq -r '.type // "pattern"' 2>/dev/null || echo "pattern")
    DESC=$(echo "$item" | jq -r '.description // ""' 2>/dev/null || true)
    CONF=$(echo "$item" | jq -r '.confidence // 0.5' 2>/dev/null || echo "0.5")

    [[ -z "$DESC" ]] && continue

    # Escape description for our output JSON
    DESC=$(printf '%s' "$DESC" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 200)

    echo "{\"type\":\"$TYPE\",\"description\":\"$DESC\",\"confidence\":$CONF,\"source\":\"deep-extract\",\"session_id\":\"$SESSION_ID\",\"timestamp\":\"$TIMESTAMP\"}" >> "$CANDIDATES_FILE"
  done

  hook_log "memory-extract-deep: analysis complete"
  return 0
}
