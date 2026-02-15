#!/bin/bash
# ClaudeTools sync engine launcher — MCP server entrypoint
# Tries multiple paths for the sync engine binary

if command -v claudetools-sync &>/dev/null; then
  exec claudetools-sync "$@"
elif [ -x "${HOME}/.claudetools/bin/claudetools-sync" ]; then
  exec "${HOME}/.claudetools/bin/claudetools-sync" "$@"
else
  exec npx -y @claudetools/sync-engine "$@"
fi
