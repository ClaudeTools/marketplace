#!/usr/bin/env bash
# submit-feedback.sh — POST a sanitized feedback JSON to the telemetry endpoint
# Usage: bash submit-feedback.sh /path/to/feedback-summary.json
#
# The JSON file must conform to the /v1/feedback POST schema.
# Exits 0 on success, 1 on failure.

set -euo pipefail

json_file="${1:-}"
if [ -z "$json_file" ] || [ ! -f "$json_file" ]; then
  echo "ERROR: Provide path to feedback JSON file"
  echo "Usage: bash submit-feedback.sh /path/to/feedback-summary.json"
  exit 1
fi

# Validate file size (50KB max)
size=$(stat -f%z "$json_file" 2>/dev/null || stat -c%s "$json_file" 2>/dev/null || echo 0)
if [ "$size" -gt 51200 ]; then
  echo "ERROR: Feedback file exceeds 50KB limit ($size bytes)"
  exit 1
fi

# Validate it's valid JSON
if ! python3 -m json.tool "$json_file" >/dev/null 2>&1; then
  if ! node -e "JSON.parse(require('fs').readFileSync('$json_file','utf8'))" 2>/dev/null; then
    echo "ERROR: File is not valid JSON"
    exit 1
  fi
fi

endpoint="https://telemetry.claudetools.com/v1/feedback"
fallback="https://claudetools-telemetry.motionmavericks.workers.dev/v1/feedback"

# Try primary endpoint first, fall back to workers.dev
http_code=$(curl -s -o /tmp/feedback-response.$$ -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 \
  -X POST -H "Content-Type: application/json" \
  --data-binary @"$json_file" \
  "$endpoint" 2>/dev/null || echo "000")

if [ "$http_code" = "000" ]; then
  # Primary failed, try fallback
  http_code=$(curl -s -o /tmp/feedback-response.$$ -w '%{http_code}' \
    --connect-timeout 5 --max-time 15 \
    -X POST -H "Content-Type: application/json" \
    --data-binary @"$json_file" \
    "$fallback" 2>/dev/null || echo "000")
fi

response=$(cat /tmp/feedback-response.$$ 2>/dev/null || echo "{}")
rm -f /tmp/feedback-response.$$ 2>/dev/null || true

if [ "$http_code" = "200" ]; then
  echo "SUCCESS: Feedback submitted (HTTP $http_code)"
  echo "Response: $response"
  exit 0
else
  echo "FAILED: HTTP $http_code"
  echo "Response: $response"
  exit 1
fi
