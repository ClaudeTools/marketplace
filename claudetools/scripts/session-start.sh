#!/bin/bash
# ClaudeTools SessionStart hook — reconcile external installs
# Tries multiple paths for the sync engine binary

if command -v claudetools-sync &>/dev/null; then
  claudetools-sync hook SessionStart
elif [ -x "${HOME}/.claudetools/bin/claudetools-sync" ]; then
  "${HOME}/.claudetools/bin/claudetools-sync" hook SessionStart
fi
# Exit 0 regardless — hook failures should not block session startup
exit 0
