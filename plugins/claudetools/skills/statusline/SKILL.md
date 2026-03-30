---
name: statusline
description: View and configure the claudetools statusline — list widgets, enable/disable them, change separator and colors
---

# Statusline Configuration

The claudetools statusline is configured at `~/.config/claudetools/statusline.json`.

## Available Widgets

| Widget | Shows | Example |
|--------|-------|---------|
| `model` | Model name | `Opus 4.6` |
| `git` | Current branch | `main` |
| `context` | Context window usage % | `42% ctx` |
| `cost` | Session cost | `$0.83` |
| `speed` | Output token rate | `16.6 tok/s` |
| `session` | 5-hour rate limit usage % | `42% 5h` |
| `weekly` | 7-day rate limit usage % | `15% 7d` |
| `duration` | Session duration | `12m` |
| `worktree` | Worktree name (if active) | `wt:hazy-noodling-stearns` |

## Actions

**List current config:**
Read `~/.config/claudetools/statusline.json` and display the current widget order, separator, and color setting.

**Enable a widget:**
Read the current config, add the widget name to the `widgets` array if not already present, write back.

**Disable a widget:**
Read the current config, remove the widget name from the `widgets` array, write back.

**Reorder widgets:**
Read the current config, set `widgets` to the new order provided by the user, write back.

**Change separator:**
Update the `separator` field (e.g., `" | "`, `" ~ "`, `" "`)

**Toggle colors:**
Set `colors` to `true` or `false`.

**Reset to defaults:**
Delete `~/.config/claudetools/statusline.json`. The renderer will recreate it from defaults on next invocation.

## Example Config

```json
{
  "widgets": ["model", "git", "context", "session", "weekly", "duration", "worktree"],
  "separator": " | ",
  "colors": true
}
```

When the user asks to change the statusline, read the current config, apply the change, and write it back. Changes take effect on the next Claude Code interaction (no restart needed).
