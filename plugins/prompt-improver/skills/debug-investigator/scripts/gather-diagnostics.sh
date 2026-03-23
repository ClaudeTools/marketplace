#!/usr/bin/env bash
# gather-diagnostics.sh — Collect diagnostic context for debugging
# Usage: bash gather-diagnostics.sh [error-description]

echo "=== Diagnostic Context ==="

# Git state
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git repo')"
echo "Recent changes to tracked files:"
git log --oneline -5 2>/dev/null || true
echo ""

# Recent test results
if [ -f /tmp/claude-test-results.txt ]; then
  echo "=== Recent Test Output (last 20 lines) ==="
  tail -20 /tmp/claude-test-results.txt
  echo ""
fi

# Check for common error log locations
for logfile in /tmp/claude-*.log logs/*.log; do
  if [ -f "$logfile" ]; then
    RECENT=$(find "$logfile" -mmin -10 2>/dev/null)
    if [ -n "$RECENT" ]; then
      echo "=== Recent log: $logfile (last 10 lines) ==="
      tail -10 "$logfile"
      echo ""
    fi
  fi
done

# Description passed as argument
if [ -n "$1" ]; then
  echo "=== Error Description ==="
  echo "$*"
fi
