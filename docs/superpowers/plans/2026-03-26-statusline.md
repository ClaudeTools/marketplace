# Claudetools Custom Statusline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a zero-dependency custom statusline that activates automatically when the claudetools plugin is installed, shows model/git/context/cost/speed/duration/worktree info, and lets users configure widgets via `~/.config/claudetools/statusline.json`.

**Architecture:** A bash+jq statusline renderer (`render.sh`) reads JSON from stdin and user settings from a config file, then outputs a formatted status bar. A SessionStart hook (`configure-statusline.sh`) auto-configures `~/.claude/settings.json` to point at the renderer. A skill (`statusline`) lets users reconfigure widgets interactively.

**Tech Stack:** Bash, jq (required dependency — already used throughout the plugin)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `plugin/scripts/statusline/render.sh` | Main renderer — reads JSON stdin + user config, outputs formatted status bar |
| `plugin/scripts/statusline/defaults.json` | Default config — shipped with plugin, copied to user config on first run |
| `plugin/scripts/statusline/configure.sh` | SessionStart hook — auto-configures `~/.claude/settings.json` if statusline is not set |
| `plugin/hooks/hooks.json` | Add new SessionStart entry for `configure.sh` |
| `plugin/skills/statusline/skill.md` | Skill to list/enable/disable/reconfigure widgets |

---

### Task 1: Create the default config and renderer skeleton

**Files:**
- Create: `plugin/scripts/statusline/defaults.json`
- Create: `plugin/scripts/statusline/render.sh`

- [ ] **Step 1: Create the default config file**

```json
{
  "widgets": ["model", "git", "context", "cost", "speed", "duration", "worktree"],
  "separator": " | ",
  "colors": true
}
```

Write to `plugin/scripts/statusline/defaults.json`.

- [ ] **Step 2: Create render.sh with argument parsing and config loading**

```bash
#!/usr/bin/env bash
# render.sh — claudetools statusline renderer
# Reads Claude Code JSON from stdin, outputs formatted status bar to stdout.
# Config: ~/.config/claudetools/statusline.json (falls back to bundled defaults)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER_CONFIG="$HOME/.config/claudetools/statusline.json"
DEFAULT_CONFIG="$SCRIPT_DIR/defaults.json"

# Load user config or create from defaults
if [[ ! -f "$USER_CONFIG" ]]; then
  mkdir -p "$(dirname "$USER_CONFIG")"
  cp "$DEFAULT_CONFIG" "$USER_CONFIG"
fi

CONFIG="$USER_CONFIG"

# Read JSON from stdin (Claude Code pipes session data)
INPUT=$(cat)

# Read config values
WIDGETS=$(jq -r '.widgets // ["model","git","context","cost","speed","duration","worktree"] | .[]' "$CONFIG")
SEPARATOR=$(jq -r '.separator // " | "' "$CONFIG")
USE_COLORS=$(jq -r '.colors // true' "$CONFIG")

# Color helpers
if [[ "$USE_COLORS" == "true" ]]; then
  DIM='\033[2m'
  RESET='\033[0m'
  BOLD='\033[1m'
  CYAN='\033[36m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  MAGENTA='\033[35m'
else
  DIM='' RESET='' BOLD='' CYAN='' GREEN='' YELLOW='' MAGENTA=''
fi

# Widget renderers — each reads from $INPUT and prints a string
widget_model() {
  local name
  name=$(echo "$INPUT" | jq -r '.model.display_name // .model.id // "unknown"')
  printf "${BOLD}%s${RESET}" "$name"
}

widget_git() {
  local branch
  branch=$(echo "$INPUT" | jq -r '.worktree.branch // empty' 2>/dev/null) || true
  if [[ -z "$branch" ]]; then
    # Fall back to git command with --no-optional-locks to avoid conflicts
    branch=$(git --no-optional-locks branch --show-current 2>/dev/null) || branch=""
  fi
  [[ -z "$branch" ]] && return
  printf "${CYAN}%s${RESET}" "$branch"
}

widget_context() {
  local pct
  pct=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')
  # Color code: green < 50, yellow 50-80, red > 80
  local color="$GREEN"
  if (( $(echo "$pct > 80" | bc -l 2>/dev/null || echo 0) )); then
    color='\033[31m'
  elif (( $(echo "$pct > 50" | bc -l 2>/dev/null || echo 0) )); then
    color="$YELLOW"
  fi
  printf "${color}%.0f%% ctx${RESET}" "$pct"
}

widget_cost() {
  local cost
  cost=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
  printf "${DIM}\$%s${RESET}" "$cost"
}

widget_speed() {
  local out_tokens duration_ms tps
  out_tokens=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0')
  duration_ms=$(echo "$INPUT" | jq -r '.cost.total_api_duration_ms // 0')
  if [[ "$duration_ms" != "0" && "$duration_ms" != "null" ]]; then
    tps=$(echo "scale=1; $out_tokens / ($duration_ms / 1000)" | bc -l 2>/dev/null || echo "0")
    printf "${DIM}%s tok/s${RESET}" "$tps"
  fi
}

widget_duration() {
  local ms mins
  ms=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
  if [[ "$ms" != "0" && "$ms" != "null" ]]; then
    mins=$(( ms / 60000 ))
    if (( mins >= 60 )); then
      printf "${DIM}%dh%dm${RESET}" $(( mins / 60 )) $(( mins % 60 ))
    else
      printf "${DIM}%dm${RESET}" "$mins"
    fi
  fi
}

widget_worktree() {
  local wt_name
  wt_name=$(echo "$INPUT" | jq -r '.worktree.name // empty' 2>/dev/null) || true
  [[ -z "$wt_name" ]] && return
  printf "${MAGENTA}wt:%s${RESET}" "$wt_name"
}

# Build output
parts=()
for w in $WIDGETS; do
  result=$(widget_"$w" 2>/dev/null) || true
  [[ -n "$result" ]] && parts+=("$result")
done

# Join with separator
output=""
for i in "${!parts[@]}"; do
  (( i > 0 )) && output+="$SEPARATOR"
  output+="${parts[$i]}"
done

printf '%b' "$output"
```

- [ ] **Step 3: Make render.sh executable**

Run: `chmod +x plugin/scripts/statusline/render.sh`

- [ ] **Step 4: Test render.sh manually with sample JSON**

Run:
```bash
echo '{"model":{"display_name":"Opus 4.6"},"context_window":{"used_percentage":42,"total_output_tokens":5000},"cost":{"total_cost_usd":0.83,"total_duration_ms":720000,"total_api_duration_ms":300000},"worktree":{"name":"hazy-noodling-stearns","branch":"feat/statusline"}}' | bash plugin/scripts/statusline/render.sh
```

Expected: A formatted line like `Opus 4.6 | feat/statusline | 42% ctx | $0.83 | 16.6 tok/s | 12m | wt:hazy-noodling-stearns`

- [ ] **Step 5: Test with colors disabled**

Run:
```bash
mkdir -p ~/.config/claudetools
echo '{"widgets":["model","context"],"separator":" - ","colors":false}' > ~/.config/claudetools/statusline.json
echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":10}}' | bash plugin/scripts/statusline/render.sh
```

Expected: `Sonnet - 10% ctx` (no ANSI escape codes)

Clean up: `rm ~/.config/claudetools/statusline.json` (so defaults get re-created on next run)

- [ ] **Step 6: Commit**

```bash
git add plugin/scripts/statusline/defaults.json plugin/scripts/statusline/render.sh
git commit -m "feat: add custom statusline renderer with configurable widgets"
```

---

### Task 2: Create the auto-configuration SessionStart hook

**Files:**
- Create: `plugin/scripts/statusline/configure.sh`
- Modify: `plugin/hooks/hooks.json` (SessionStart section, around line 259)

- [ ] **Step 1: Create configure.sh**

```bash
#!/usr/bin/env bash
# configure.sh — SessionStart hook: auto-configure statusline in ~/.claude/settings.json
# Idempotent: skips if user already has a statusline configured.
# Always exits 0 to never block session startup.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
RENDER_SCRIPT='${CLAUDE_PLUGIN_ROOT}/scripts/statusline/render.sh'

# Ensure settings.json exists
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

# Check if statusLine is already configured
existing=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || true

if [[ -n "$existing" ]]; then
  # User already has a statusline configured — don't overwrite
  exit 0
fi

# Add statusline config
jq --arg cmd "bash $RENDER_SCRIPT" \
  '.statusLine = {"type": "command", "command": $cmd}' \
  "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"

exit 0
```

- [ ] **Step 2: Make configure.sh executable**

Run: `chmod +x plugin/scripts/statusline/configure.sh`

- [ ] **Step 3: Add SessionStart hook entry to hooks.json**

Add a new entry to the `"SessionStart"` array in `plugin/hooks/hooks.json`. Insert it after the existing entries (after `inject-session-context.sh`):

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/scripts/statusline/configure.sh",
      "timeout": 5
    }
  ]
}
```

- [ ] **Step 4: Test configure.sh on a clean settings file**

Run:
```bash
# Back up current settings
cp ~/.claude/settings.json ~/.claude/settings.json.bak

# Test with no statusLine
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/test-settings.json
SETTINGS_OVERRIDE=/tmp/test-settings.json bash plugin/scripts/statusline/configure.sh
jq '.statusLine' /tmp/test-settings.json
```

Wait — `configure.sh` uses `$HOME/.claude/settings.json` directly. For testing, temporarily rename:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq 'del(.statusLine)' ~/.claude/settings.json.bak > ~/.claude/settings.json
bash plugin/scripts/statusline/configure.sh
jq '.statusLine' ~/.claude/settings.json
```

Expected:
```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/statusline/render.sh"
}
```

Restore: `cp ~/.claude/settings.json.bak ~/.claude/settings.json`

- [ ] **Step 5: Test idempotency — running again should not overwrite**

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
bash plugin/scripts/statusline/configure.sh
diff ~/.claude/settings.json ~/.claude/settings.json.bak
```

Expected: No difference (existing config preserved).

Restore: `cp ~/.claude/settings.json.bak ~/.claude/settings.json`

- [ ] **Step 6: Commit**

```bash
git add plugin/scripts/statusline/configure.sh plugin/hooks/hooks.json
git commit -m "feat: auto-configure statusline on SessionStart"
```

---

### Task 3: Create the statusline skill for user reconfiguration

**Files:**
- Create: `plugin/skills/statusline/skill.md`

- [ ] **Step 1: Create the statusline skill**

```markdown
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
  "widgets": ["model", "git", "context", "cost", "speed", "duration", "worktree"],
  "separator": " | ",
  "colors": true
}
```

When the user asks to change the statusline, read the current config, apply the change, and write it back. Changes take effect on the next Claude Code interaction (no restart needed).
```

Write to `plugin/skills/statusline/skill.md`.

- [ ] **Step 2: Commit**

```bash
git add plugin/skills/statusline/skill.md
git commit -m "feat: add /statusline skill for widget configuration"
```

---

### Task 4: End-to-end verification

**Files:** None (read-only verification)

- [ ] **Step 1: Verify render.sh with all widgets**

```bash
echo '{"model":{"display_name":"Opus 4.6","id":"claude-opus-4-6"},"context_window":{"used_percentage":42,"total_output_tokens":12000,"context_window_size":200000},"cost":{"total_cost_usd":0.83,"total_duration_ms":720000,"total_api_duration_ms":300000},"worktree":{"name":"hazy-noodling-stearns","branch":"feat/statusline"}}' | bash plugin/scripts/statusline/render.sh
```

Expected: All 7 widgets rendered with color codes, separated by ` | `.

- [ ] **Step 2: Verify render.sh handles missing/null fields gracefully**

```bash
echo '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":null},"cost":{}}' | bash plugin/scripts/statusline/render.sh
```

Expected: Only `model` widget renders (others skip gracefully when data is null/missing). No errors on stderr.

- [ ] **Step 3: Verify render.sh with empty stdin**

```bash
echo '{}' | bash plugin/scripts/statusline/render.sh
```

Expected: Renders `unknown` for model, skips other widgets. No crash.

- [ ] **Step 4: Verify configure.sh doesn't touch existing statusline**

```bash
# Current settings already have ccstatusline configured
jq '.statusLine' ~/.claude/settings.json
```

Expected: Still shows the existing `npx -y ccstatusline@latest` config, not overwritten.

- [ ] **Step 5: Verify hooks.json is valid JSON**

```bash
jq empty plugin/hooks/hooks.json && echo "valid JSON"
```

Expected: `valid JSON`

- [ ] **Step 6: Syntax check all new scripts**

```bash
bash -n plugin/scripts/statusline/render.sh && echo "render.sh OK"
bash -n plugin/scripts/statusline/configure.sh && echo "configure.sh OK"
```

Expected: Both print OK.

- [ ] **Step 7: Verify widget subset works**

```bash
echo '{"widgets":["model","cost"],"separator":" ~ ","colors":false}' > ~/.config/claudetools/statusline.json
echo '{"model":{"display_name":"Sonnet 4.6"},"cost":{"total_cost_usd":1.23}}' | bash plugin/scripts/statusline/render.sh
rm ~/.config/claudetools/statusline.json
```

Expected: `Sonnet 4.6 ~ $1.23` (no ANSI codes, custom separator, only 2 widgets).

---

### Task 5: Sync to publishable artifacts

**Files:**
- Sync: `plugin/` -> `plugins/claudetools/`

- [ ] **Step 1: Sync plugin to publishable directory**

```bash
rsync -a --delete --exclude='.git' --exclude='node_modules' --exclude='logs/' plugin/ plugins/claudetools/
```

- [ ] **Step 2: Verify synced files exist**

```bash
ls -la plugins/claudetools/scripts/statusline/
ls plugins/claudetools/skills/statusline/
```

Expected: `render.sh`, `configure.sh`, `defaults.json`, and `skill.md` all present.

- [ ] **Step 3: Commit sync**

```bash
git add plugins/claudetools/
git commit -m "chore: sync statusline feature to publishable artifacts"
```
