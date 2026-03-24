---
title: "Installation"
description: "Installation — claudetools documentation."
---
## Install

```
/plugin install claudetools@claudetools-marketplace
```

No configuration required. Hooks activate immediately after install.

## What happens on install

- **Hooks activate** — 51 hooks across 17 lifecycle events start running on every tool call
- **Skills become available** — invoke via `/skill-name` or let Claude trigger them automatically
- **Codebase indexing** — the codebase-pilot index builds at the start of your next session

## Requirements

| Requirement | Version |
|-------------|---------|
| Claude Code | v1.0+ |
| Node.js | 18+ |
| SQLite3 | any recent |
| jq | recommended |

## Verify the install

Run `/session-dashboard` after your first session to confirm hooks are firing. You should see hook fire counts, block rates, and tool success metrics.

## Update

```
/plugin update claudetools
```

## Quiet mode

Suppress non-safety hooks for research sessions where hook output would be distracting:

```bash
CLAUDE_HOOKS_QUIET=1 claude
```

Safety hooks always run regardless of quiet mode.
