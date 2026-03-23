#!/usr/bin/env bash
# gather-diff.sh — Collect code changes for review
# Usage: bash gather-diff.sh [file|branch|empty]

ARG="${1:-}"

if [ -z "$ARG" ]; then
  # No argument: show uncommitted changes
  if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    # No uncommitted changes, show last commit
    echo "=== Last commit ==="
    git log --oneline -1
    echo ""
    git diff HEAD~1..HEAD
  else
    echo "=== Uncommitted changes ==="
    git diff
    git diff --cached
  fi
elif [ -f "$ARG" ]; then
  # File path: show that file
  echo "=== File: $ARG ==="
  cat "$ARG"
elif git rev-parse --verify "$ARG" 2>/dev/null; then
  # Branch name: diff against main
  MAIN=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
  echo "=== Diff: $MAIN..$ARG ==="
  git diff "$MAIN".."$ARG"
else
  echo "Error: '$ARG' is not a file or branch"
  exit 1
fi
