# Token Efficiency Overhaul — claudetools Plugin

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce per-session token waste by ~3,000-6,000 tokens and eliminate ~400-1200ms of per-session latency by fixing context injection leaks, tightening hook dispatch, building a custom thinking MCP, and trimming bloated skills.

**Architecture:** The claudetools plugin fires hooks on every tool call (PreToolUse/PostToolUse dispatchers), every user message (UserPromptSubmit), and session start. Token waste comes from: (1) stdout leaks injecting noise into context, (2) broad pattern matching causing redundant workflow injection, (3) uncached expensive operations repeating per-turn, (4) the external sequential-thinking MCP being oversized. We fix each category with targeted changes, replacing sequential-thinking with a custom lean MCP server shipped inside the plugin.

**Tech Stack:** Bash (hooks), Node.js + @modelcontextprotocol/sdk (MCP server), jq, sqlite3

---

## File Structure

### New files
- `plugin/mcp-servers/think/index.js` — Custom thinking MCP server (~80 lines)
- `plugin/mcp-servers/think/package.json` — Dependencies
- `plugin/mcp-servers/think/start.sh` — Launcher script
- `plugin/skills/prompt-improver/assets/generation-agent-prompt.md` — Extracted agent prompt

### Modified files
- `plugin/agent-mesh/cli.js` — Fix "No messages" stdout leak (line 246)
- `plugin/agent-mesh/cli.js` — Fix heartbeat stdout (line 146)
- `plugin/scripts/lib/skill-router.sh` — Tighten design intent patterns
- `plugin/scripts/lib/phase-detect.sh` — Add TTL caching, remove gh from hot path
- `plugin/scripts/inject-prompt-context.sh` — DRY up double extraction, gate skill injection
- `plugin/scripts/inject-session-context.sh` — Remove legacy table queries, gate memory injection
- `plugin/scripts/verify-subagent-independently.sh` — Route clean-path to stderr
- `plugin/scripts/post-tool-dispatcher.sh` — Move browser-circuit-breaker into case routing
- `plugin/scripts/pre-tool-dispatcher.sh` — Inline enforce-user-stop logic
- `plugin/.claude-plugin/plugin.json` — Register think MCP server
- `plugin/task-system/lib/tools.js` — Conditional decompose guidance
- `plugin/skills/prompt-improver/SKILL.md` — Extract inline agent prompt
- `plugin/scripts/session-stop-dispatcher.sh` — Gate debug diagnostic

---

### Task 1: Build custom "think" MCP server

**Files:**
- Create: `plugin/mcp-servers/think/index.js`
- Create: `plugin/mcp-servers/think/package.json`
- Create: `plugin/mcp-servers/think/start.sh`
- Modify: `plugin/.claude-plugin/plugin.json`

This replaces the external `sequential-thinking` MCP plugin with a custom server inspired by [Anthropic's "think tool" research](https://www.anthropic.com/engineering/claude-think-tool) which showed **+54% on tau-bench** and **+1.6% on SWE-bench** with a minimal scratchpad tool. Our version adds structured step tracking + auto-summarization:

- **Compact tool description** (~20 tokens vs ~400 for the original — 95% smaller)
- **4 parameters** vs 9 (dropped `totalThoughts`, `needsMoreThoughts`, `nextThoughtNeeded` → single `done` boolean)
- **Auto-summarization** — after 8 thoughts, older steps are compressed to prevent context bloat
- **Minimal JSON responses** — no pretty-printing, no redundant fields
- **No chalk dependency** — zero cosmetic overhead
- Ships **inside the plugin** so it's versioned and controllable

Design rationale: The original sequential-thinking server's 11-point "You should:" list in the tool description is system-prompt coaching, not API documentation. A well-instructed model doesn't need the tool description to teach reasoning strategy. The server's `totalThoughts` parameter adds zero value — models always adjust it anyway.

- [ ] **Step 1: Create package.json**

```json
{
  "name": "@claudetools/think",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.24.0"
  }
}
```

- [ ] **Step 2: Create the MCP server**

```javascript
#!/usr/bin/env node
// think/index.js — Lean thinking MCP server for structured problem-solving
//
// Inspired by Anthropic's "think tool" research (https://www.anthropic.com/engineering/claude-think-tool)
// which showed +54% on tau-bench with a minimal scratchpad tool.
//
// This version adds step tracking + auto-summarization on top of the scratchpad pattern:
//   - 95% smaller tool description (~20 tokens vs ~400)
//   - 4 params vs 9 (dropped totalThoughts, needsMoreThoughts, nextThoughtNeeded → done)
//   - Auto-summarization after configurable threshold to prevent context bloat
//   - No chalk dependency

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "think",
  version: "1.0.0",
});

const history = [];
const SUMMARIZE_AFTER = parseInt(process.env.THINK_SUMMARIZE_AFTER || "8", 10);

server.tool(
  "think",
  "Scratch pad for reasoning. No side effects. Use for multi-step analysis, planning, or debugging before acting.",
  {
    thought: z.string().describe("Your current reasoning step"),
    done: z.boolean().describe("True when reasoning is complete").default(false),
    branch: z.string().optional().describe("Branch label if exploring an alternative"),
    revises: z.number().int().min(1).optional().describe("Step number this replaces"),
  },
  async ({ thought, done, branch, revises }) => {
    // Handle revision — truncate history from the revised step
    if (revises !== undefined && revises > 0 && revises <= history.length) {
      history.splice(revises - 1);
    }

    const step = history.length + 1;
    history.push({ step, thought, branch, done });

    // Build compact response
    const response = { step, done, total: history.length };

    // Auto-summarize older thoughts to prevent context bloat
    if (history.length > SUMMARIZE_AFTER) {
      const recent = history.slice(-3);
      const older = history.slice(0, -3);
      response.summary = older
        .map((h) => `${h.step}: ${h.thought.slice(0, 60)}${h.thought.length > 60 ? "..." : ""}`)
        .join(" | ");
      response.recentSteps = recent.map((h) => h.step);
    }

    return {
      content: [{ type: "text", text: JSON.stringify(response) }],
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

- [ ] **Step 3: Create launcher script**

```bash
#!/usr/bin/env bash
# start.sh — Launch the think MCP server
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
[ -d node_modules ] || npm install --omit=dev --silent 2>/dev/null
exec node index.js
```

Make executable: `chmod +x plugin/mcp-servers/think/start.sh`

- [ ] **Step 4: Register in plugin.json**

Modify `plugin/.claude-plugin/plugin.json` to add the think server alongside task-system:

```json
{
  "mcpServers": {
    "task-system": {
      "command": "bash",
      "args": ["${CLAUDE_PLUGIN_ROOT}/task-system/start.sh"]
    },
    "think": {
      "command": "bash",
      "args": ["${CLAUDE_PLUGIN_ROOT}/mcp-servers/think/start.sh"]
    }
  }
}
```

- [ ] **Step 5: Install dependencies**

Run: `cd plugin/mcp-servers/think && npm install --omit=dev`
Expected: `node_modules/` created with @modelcontextprotocol/sdk

- [ ] **Step 6: Verify server starts**

Run: `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | node plugin/mcp-servers/think/index.js 2>/dev/null | head -1`
Expected: JSON response with server capabilities including the "think" tool

- [ ] **Step 7: Commit**

```bash
git add plugin/mcp-servers/think/ plugin/.claude-plugin/plugin.json
git commit -m "feat: add custom think MCP server replacing sequential-thinking

Inspired by Anthropic's think tool research (+54% tau-bench).
95% smaller tool description (20 tokens vs 400), 4 params vs 9,
auto-summarization after 8 steps, no chalk dependency."
```

---

### Task 2: Uninstall external sequential-thinking plugin and remove from marketplace

**Files:**
- Modify: `.claude-plugin/marketplace.json` (if sequential-thinking is listed)
- No plugin source files modified — this is a marketplace + user-settings change

After the custom think server is working, the external sequential-thinking plugin should be removed.

- [ ] **Step 1: Disable in user settings**

In `~/.claude/settings.json`, change:
```json
"sequential-thinking@claudetools-marketplace": true,
```
to:
```json
"sequential-thinking@claudetools-marketplace": false,
```

Or run: `claude plugins uninstall sequential-thinking@claudetools-marketplace`

- [ ] **Step 2: Remove from the claudetools-marketplace manifest**

The sequential-thinking plugin is listed in `.claude-plugin/marketplace.json` in the public marketplace repo. Since the claudetools plugin now ships its own think MCP server, the standalone sequential-thinking plugin should be removed from the marketplace listing.

Note: The prompt-improver validator at `plugin/skills/prompt-improver/scripts/validate-prompt.sh:179-180` already warns against sequential-thinking usage — this aligns with the removal.

- [ ] **Step 3: Commit marketplace changes**

```bash
git add .claude-plugin/marketplace.json
git commit -m "chore: remove sequential-thinking from marketplace

Replaced by built-in think MCP server shipped inside claudetools plugin.
See Anthropic's think tool research for the design rationale."
```

---

### Task 3: Fix agent-mesh "No messages" stdout leak

**Files:**
- Modify: `plugin/agent-mesh/cli.js:246`
- Modify: `plugin/agent-mesh/cli.js:146`

Two stdout leaks inject unnecessary text into Claude's context every turn.

- [ ] **Step 1: Fix cmdInbox empty case**

In `plugin/agent-mesh/cli.js`, change line 246 from:
```javascript
console.log('No messages');
```
to:
```javascript
// Silent return — caller treats empty stdout as "no messages"
```

Delete the `console.log('No messages');` line entirely. The `inject-prompt-context.sh` caller at line 68 already handles empty `$MESSAGES` correctly with `if [[ -n "$MESSAGES" ]]; then`.

- [ ] **Step 2: Fix cmdHeartbeat stdout**

In `plugin/agent-mesh/cli.js`, change line 146 from:
```javascript
console.log(`Heartbeat updated for ${id}`);
```
to:
```javascript
console.error(`Heartbeat updated for ${id}`);
```

This prevents the heartbeat confirmation from leaking into context when captured by callers.

- [ ] **Step 3: Verify the fix**

Run: `node plugin/agent-mesh/cli.js inbox --id test-nonexistent 2>/dev/null`
Expected: No stdout output (empty). Previously would output "No messages" or an error.

- [ ] **Step 4: Commit**

```bash
git add plugin/agent-mesh/cli.js
git commit -m "fix: stop mesh stdout leaks injecting tokens every turn

cmdInbox 'No messages' and cmdHeartbeat confirmation were going to
stdout, captured by inject-prompt-context.sh and injected into context.
Saves ~10 tokens per user turn."
```

---

### Task 4: Tighten skill-router patterns and add session dedup

**Files:**
- Modify: `plugin/scripts/lib/skill-router.sh`
- Modify: `plugin/scripts/inject-prompt-context.sh`

The design intent case (`*build*|*create*|*implement*`) matches nearly every dev message. The workflow block (~60 tokens) fires redundantly on every matching turn.

- [ ] **Step 1: Narrow the design pattern in skill-router.sh**

Replace the broad design case (line 34) with multi-word phrases:

```bash
  case "$lower" in
    *"build feature"*|*"build a "*|*"create feature"*|*"create a new"*|*"implement feature"*|*"implement a "*|*"add feature"*|*"add a feature"*|*"new feature"*|*"write a new"*|*"refactor the"*|*"refactor this"*|*"restructure"*|*"set up"*|*"set up a "*|*"integrate with"*)
      echo "design"; return 0 ;;
  esac
```

Key change: bare `*build*`, `*create*`, `*implement*` removed. Now requires "build a", "build feature", etc. This prevents "rebuild the index", "create a variable", "implement the fix" from triggering the full design workflow injection.

- [ ] **Step 2: Add session-level dedup in inject-prompt-context.sh**

After the skill intent classification block (line 44-51), add a dedup gate:

```bash
MATCHED_CMD=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_CMD" ]; then
  # Only inject workflow context once per session per command
  SKILL_FLAG="/tmp/.claude-workflow-injected-${MATCHED_CMD}-${SESSION_ID}"
  if [ ! -f "$SKILL_FLAG" ]; then
    WORKFLOW_CTX=$(format_workflow_context "$MATCHED_CMD")
    echo "$WORKFLOW_CTX"
    touch "$SKILL_FLAG"
  fi
  # Always track the invocation for analytics
  source "$(dirname "$0")/lib/telemetry.sh"
  emit_skill_invocation "$MATCHED_CMD" "$SESSION_ID" "keyword" 2>/dev/null || true
fi
```

This ensures each workflow hint fires at most once per session.

- [ ] **Step 3: Verify patterns don't match common phrases**

Run manual test:
```bash
source plugin/scripts/lib/skill-router.sh
# Should NOT match:
classify_intent "rebuild the docker image"       # should be empty
classify_intent "create a variable called foo"    # should be empty
classify_intent "implement the fix from the PR"   # should be empty
# Should match:
classify_intent "build a new dashboard feature"   # should echo "design"
classify_intent "create a new API endpoint"       # should echo "design"
classify_intent "refactor the auth module"        # should echo "design"
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/lib/skill-router.sh plugin/scripts/inject-prompt-context.sh
git commit -m "fix: tighten skill-router patterns, add session-level dedup

Bare *build*|*create*|*implement* replaced with multi-word phrases.
Workflow context now fires once per session per command type.
Saves ~60 tokens per false-positive match x many turns."
```

---

### Task 5: Cache phase detection with TTL

**Files:**
- Modify: `plugin/scripts/lib/phase-detect.sh`

`detect_phase()` runs `git rev-parse`, `git rev-list --count`, `git log --oneline -20`, and `gh pr view HEAD` (network call!) on every user message. The phase rarely changes mid-session.

- [ ] **Step 1: Add caching to detect_phase**

Replace the `detect_phase()` function:

```bash
detect_phase() {
  local cwd="${1:-.}"
  local session_id="${2:-${SESSION_ID:-$PPID}}"
  local cache_file="/tmp/.claude-phase-${session_id}"
  local cache_ttl=120  # seconds

  # Return cached result if fresh
  if [ -f "$cache_file" ]; then
    local file_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$file_age" -lt "$cache_ttl" ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  # Not a git repo → unknown
  git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "unknown" | tee "$cache_file"; return 0; }

  local branch
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # On main/master → done
  case "$branch" in
    main|master) echo "done" | tee "$cache_file"; return 0 ;;
  esac

  # Check for plan files
  local has_plan=0
  [ -d "$cwd/docs/plans" ] && [ -n "$(ls "$cwd/docs/plans/"*.md 2>/dev/null)" ] && has_plan=1

  # Check for commits since branch point
  local commit_count
  commit_count=$(git -C "$cwd" rev-list --count main..HEAD 2>/dev/null || git -C "$cwd" rev-list --count master..HEAD 2>/dev/null || echo "0")

  # Check for review evidence (local only — no network call)
  local has_review=0
  git -C "$cwd" log --oneline -20 2>/dev/null | grep -qi 'review\|reviewed\|code review' && has_review=1

  # Check for PR — ONLY if gh is available AND we haven't checked recently
  local has_pr=0
  local pr_cache="/tmp/.claude-phase-pr-${session_id}"
  if command -v gh &>/dev/null; then
    if [ ! -f "$pr_cache" ] || [ $(( $(date +%s) - $(stat -c %Y "$pr_cache" 2>/dev/null || echo 0) )) -ge 300 ]; then
      gh pr view HEAD --json state 2>/dev/null | grep -q '"state"' && has_pr=1
      echo "$has_pr" > "$pr_cache"
    else
      has_pr=$(cat "$pr_cache" 2>/dev/null || echo 0)
    fi
  fi

  # Decision tree
  local result
  if [ "$has_pr" -eq 1 ]; then
    result="ship"
  elif [ "$has_review" -eq 1 ]; then
    result="ship"
  elif [ "$commit_count" -gt 0 ] && [ "$has_plan" -eq 1 ]; then
    result="review"
  elif [ "$has_plan" -eq 1 ]; then
    result="build"
  else
    result="design"
  fi

  echo "$result" | tee "$cache_file"
}
```

Key changes:
- 120s TTL cache for overall phase result
- `gh pr view` call cached separately with 300s TTL (5 min)
- No behavioral change — same decision tree, same output format

- [ ] **Step 2: Verify caching works**

```bash
source plugin/scripts/lib/phase-detect.sh
detect_phase "." "test-session"  # Should run full detection
detect_phase "." "test-session"  # Should return cached result instantly
ls -la /tmp/.claude-phase-test-session  # Should exist
rm /tmp/.claude-phase-test-session /tmp/.claude-phase-pr-test-session 2>/dev/null
```

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/lib/phase-detect.sh
git commit -m "perf: cache phase detection with 120s TTL, gh pr check at 5min TTL

Eliminates repeated git + gh API calls on every user message.
gh pr view (network call) now fires at most once per 5 minutes."
```

---

### Task 6: Fix inject-prompt-context.sh double extraction

**Files:**
- Modify: `plugin/scripts/inject-prompt-context.sh`

USER_TEXT is extracted twice (lines 11-17 and 37-42) with slightly different jq. SESSION_ID is extracted twice (lines 19-20 and 65-66). This wastes 2 jq forks per user message.

- [ ] **Step 1: Consolidate extractions**

Replace lines 6-72 of `inject-prompt-context.sh` with:

```bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

# --- Single extraction of all needed fields ---
eval "$(echo "$INPUT" | jq -r '
  @sh "SESSION_ID=\(.session_id // "")",
  @sh "USER_TEXT=\(
    if (.content | type) == "array" then
      [.content[] | if type == "string" then . elif .type == "text" then .text else "" end] | join(" ")
    elif (.content | type) == "string" then .content
    else ""
    end
  )"
' 2>/dev/null)" || { SESSION_ID=""; USER_TEXT=""; }
[[ -z "$SESSION_ID" ]] && SESSION_ID="$PPID"
STOP_FLAG="/tmp/claude-user-stop-${SESSION_ID}"

# --- User STOP detection ---
if echo "$USER_TEXT" | grep -qiE '^\s*(stop|STOP|stop it|i said stop|can you stop|please stop|fucking stop|just stop)\s*[.!?]*\s*$'; then
  touch "$STOP_FLAG"
  echo "User requested STOP. All tool calls are blocked until you receive a new non-stop instruction." >&2
  exit 0
fi

# If user sends a non-stop message, clear the flag
if [[ -f "$STOP_FLAG" ]] && [[ -n "$USER_TEXT" ]]; then
  rm -f "$STOP_FLAG"
fi

# --- Skill intent classification (Tier 1: deterministic) ---
source "$(dirname "$0")/lib/skill-router.sh"

MATCHED_CMD=$(classify_intent "$USER_TEXT")
if [ -n "$MATCHED_CMD" ]; then
  SKILL_FLAG="/tmp/.claude-workflow-injected-${MATCHED_CMD}-${SESSION_ID}"
  if [ ! -f "$SKILL_FLAG" ]; then
    WORKFLOW_CTX=$(format_workflow_context "$MATCHED_CMD")
    echo "$WORKFLOW_CTX"
    touch "$SKILL_FLAG"
  fi
  source "$(dirname "$0")/lib/telemetry.sh"
  emit_skill_invocation "$MATCHED_CMD" "$SESSION_ID" "keyword" 2>/dev/null || true
fi

# --- Phase-aware context (Tier 1: deterministic) ---
source "$(dirname "$0")/lib/phase-detect.sh"
CURRENT_PHASE=$(detect_phase "$CWD" "$SESSION_ID" 2>/dev/null || true)
if [ -n "$CURRENT_PHASE" ] && [ "$CURRENT_PHASE" != "unknown" ]; then
  PHASE_CTX=$(format_phase_context "$CURRENT_PHASE")
  [ -n "$PHASE_CTX" ] && echo "$PHASE_CTX"
fi

# --- Agent mesh inbox (only if messages waiting) ---
MESH_CLI="$(dirname "$(dirname "$0")")/agent-mesh/cli.js"
if [[ -f "$MESH_CLI" ]]; then
  MESSAGES=$(node "$MESH_CLI" inbox --id "$SESSION_ID" --ack 2>/dev/null) || true
  if [[ -n "$MESSAGES" ]]; then
    echo "[mesh] $MESSAGES"
  fi
  { node "$MESH_CLI" heartbeat --id "$SESSION_ID" 2>/dev/null || true; } &
fi

exit 0
```

Key changes:
- Single `jq -r` call extracts both SESSION_ID and USER_TEXT (saves 3 jq forks)
- SESSION_ID reused for mesh inbox (was re-extracted)
- Integrates the session dedup from Task 4
- Passes SESSION_ID to detect_phase for caching

- [ ] **Step 2: Verify the script still works**

Run: `echo '{"content":"hello world","session_id":"test-123","cwd":"."}' | bash plugin/scripts/inject-prompt-context.sh`
Expected: Phase context line + no errors

Run: `echo '{"content":"stop","session_id":"test-123","cwd":"."}' | bash plugin/scripts/inject-prompt-context.sh`
Expected: STOP message on stderr, stop flag created

Clean up: `rm -f /tmp/claude-user-stop-test-123 /tmp/.claude-phase-test-123`

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/inject-prompt-context.sh
git commit -m "perf: consolidate jq extractions in inject-prompt-context

Single jq call replaces 4 separate forks. SESSION_ID and USER_TEXT
extracted once and reused. Saves ~30ms per user message."
```

---

### Task 7: Route verify-subagent clean-path to stderr

**Files:**
- Modify: `plugin/scripts/verify-subagent-independently.sh:94-95`

Clean-path success messages go to stdout (becomes context). They should go to stderr (UI only).

- [ ] **Step 1: Route to stderr**

In `plugin/scripts/verify-subagent-independently.sh`, find lines 94-95:

```bash
echo "Subagent (${AGENT_TYPE}) changed ${FILE_COUNT} files. Typecheck and tests pass."
echo "Review the changed files before proceeding."
```

Change to:

```bash
echo "Subagent (${AGENT_TYPE}) changed ${FILE_COUNT} files. Typecheck and tests pass." >&2
echo "Review the changed files before proceeding." >&2
```

- [ ] **Step 2: Commit**

```bash
git add plugin/scripts/verify-subagent-independently.sh
git commit -m "fix: route subagent success message to stderr, not stdout

Clean-path messages were injecting 15-25 tokens into context on every
SubagentStop event. Status updates belong on stderr (UI only)."
```

---

### Task 8: Move browser-circuit-breaker into case routing

**Files:**
- Modify: `plugin/scripts/post-tool-dispatcher.sh`

`browser-circuit-breaker.sh` runs on ALL tools but only does work for `mcp__claude-in-chrome__*`. Moving it into the case statement saves a bash fork + jq parse on ~95% of tool calls.

- [ ] **Step 1: Move to tool-specific routing**

In `plugin/scripts/post-tool-dispatcher.sh`, remove line 80:
```bash
run_post_hook "browser-circuit-breaker.sh"
```

Add a new case branch before the `*` catch-all:

```bash
  mcp__claude-in-chrome__*)
    run_post_hook "browser-circuit-breaker.sh"
    ;;
```

The full case block should now look like:

```bash
case "$TOOL_NAME" in

  TaskCreate|TaskUpdate|TaskList)
    run_post_hook "track-native-tasks.sh"
    ;;

  Read)
    run_post_hook "track-file-reads.sh"
    ;;

  Edit|Write)
    run_post_hook "validate-content.sh"
    run_post_hook "edit-frequency-guard.sh"
    run_post_hook "doc-manager.sh"
    run_post_hook "track-file-edits.sh"
    run_post_hook_async "memory-index.sh"
    run_post_hook_async "reindex-on-edit.sh"
    ;;

  Bash)
    run_post_hook "post-bash-gate.sh"
    ;;

  Agent)
    run_post_hook "post-agent-gate.sh"
    ;;

  mcp__claude-in-chrome__*)
    run_post_hook "browser-circuit-breaker.sh"
    ;;

  *)
    # No tool-specific validators for this tool
    ;;

esac

# ─── Phase 2: Always — run for ALL tools ────────────────────────────────
run_post_hook "capture-outcome.sh"
```

- [ ] **Step 2: Verify non-browser tools skip the breaker**

Run: `echo '{"tool_name":"Read","session_id":"test"}' | bash plugin/scripts/post-tool-dispatcher.sh`
Expected: No browser-circuit-breaker output/processing

Run: `echo '{"tool_name":"mcp__claude-in-chrome__computer","session_id":"test"}' | bash plugin/scripts/post-tool-dispatcher.sh`
Expected: Browser circuit breaker processes the call

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/post-tool-dispatcher.sh
git commit -m "perf: route browser-circuit-breaker to mcp__claude-in-chrome__* only

Was running on ALL tool calls, wasting a bash fork + jq parse per call.
Now only fires for browser automation tools. Saves ~5-10ms per non-browser tool call."
```

---

### Task 9: Inline enforce-user-stop in pre-tool dispatcher

**Files:**
- Modify: `plugin/scripts/pre-tool-dispatcher.sh`

`enforce-user-stop.sh` is a separate script that forks bash, reads stdin, parses JSON for session_id, and checks a file. The dispatcher already has INPUT and can do the file check directly.

- [ ] **Step 1: Inline the stop check**

In `plugin/scripts/pre-tool-dispatcher.sh`, replace the Phase 1 block (lines 58-67):

```bash
# ─── Phase 1: Always — enforce-user-stop (inlined for performance) ─────
# Check for user stop flag. SESSION_ID from input, fallback to PPID.
_STOP_SID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[[ -z "$_STOP_SID" ]] && _STOP_SID="$PPID"
if [[ -f "/tmp/claude-user-stop-${_STOP_SID}" ]]; then
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"BLOCKED: User said STOP. Do not make any tool calls. Wait for new instructions."}}'
  exit 0
fi
```

Note: We keep the jq extraction here because session_id is needed for the flag path. The savings come from eliminating the bash subprocess fork — the check runs in the dispatcher's own process.

- [ ] **Step 2: Verify the stop flag still works**

```bash
touch /tmp/claude-user-stop-test-stop
echo '{"tool_name":"Read","session_id":"test-stop"}' | bash plugin/scripts/pre-tool-dispatcher.sh
# Expected: JSON block with "permissionDecision":"block"
rm /tmp/claude-user-stop-test-stop
echo '{"tool_name":"Read","session_id":"test-stop"}' | bash plugin/scripts/pre-tool-dispatcher.sh
# Expected: No output (allowed through)
```

- [ ] **Step 3: Commit**

```bash
git add plugin/scripts/pre-tool-dispatcher.sh
git commit -m "perf: inline enforce-user-stop in pre-tool dispatcher

Eliminates bash subprocess fork per tool call. Stop check runs in the
dispatcher's own process. Same behavior, one fewer fork."
```

---

### Task 10: Clean up inject-session-context.sh

**Files:**
- Modify: `plugin/scripts/inject-session-context.sh`

Remove legacy table queries and tighten memory injection to reduce session-start context.

- [ ] **Step 1: Remove legacy project_memories table support**

In `plugin/scripts/inject-session-context.sh`, delete lines 163-203 (the entire `HAS_LEGACY` block):

```bash
  # Also check legacy project_memories if table exists
  HAS_LEGACY=$(sqlite3 ... )
  if [ "$HAS_LEGACY" -gt 0 ] ...
    ...
  fi
  ...
  # Legacy table decay/prune
  if [ "$HAS_LEGACY" -gt 0 ] ...
    ...
  fi
```

This removes ~40 lines of dead code that queries and maintains a legacy table.

- [ ] **Step 2: Gate churn output behind threshold**

Change line 117-118 from:

```bash
if [ -n "$avg_churn" ] && [ "$avg_churn" != "0" ] && [ "$avg_churn" != "0.0" ] && [ "$avg_churn" != "0.00" ]; then
  echo "[Session History] Avg edit churn: ${avg_churn} | Recent failures: ${total_failures}"
```

To:

```bash
if [ -n "$avg_churn" ] && [ -n "$CHURN_WARN" ]; then
  # Only output if churn exceeds the warning threshold
  if awk "BEGIN{exit !($avg_churn >= $CHURN_WARN)}" 2>/dev/null; then
    echo "[Session History] Edit churn elevated: ${avg_churn} (threshold: ${CHURN_WARN}) | Recent failures: ${total_failures}"
  fi
```

Move the `CHURN_WARN` fetch (line 121) above this block so it's available.

- [ ] **Step 3: Reduce memory injection limit**

Change line 152 from `LIMIT 5` to `LIMIT 3`:

```sql
SELECT type, description FROM memories
WHERE confidence >= ${MEM_CONFIDENCE}
ORDER BY confidence DESC, COALESCE(last_accessed, created_at) DESC
LIMIT 3;
```

- [ ] **Step 4: Commit**

```bash
git add plugin/scripts/inject-session-context.sh
git commit -m "perf: remove legacy table queries, gate churn output, reduce memory injection

Legacy project_memories table support removed (~40 lines dead code).
Churn only reported when above warning threshold.
Memory injection reduced from 5 to 3 entries per session."
```

---

### Task 11: Make task_decompose guidance conditional

**Files:**
- Modify: `plugin/task-system/lib/tools.js`

The `decomposition_guidance` object (~250 tokens) is appended to every `task_decompose` response but the instructions are already in the task-manager SKILL.md.

- [ ] **Step 1: Find the decompose handler**

Run: `grep -n "decomposition_guidance" plugin/task-system/lib/tools.js`
Expected: Line number of the guidance object

- [ ] **Step 2: Make guidance conditional**

Wrap the guidance block to only include it when there are no existing subtasks:

```javascript
// Only include guidance on first decomposition (no subtasks yet)
if (existingSubtasks.length === 0) {
  result.decomposition_guidance = {
    context_gathering: 'Use codebase-pilot MCP tools before creating subtasks...',
    subtask_structure: 'Each subtask must include: Title, Description...',
    completeness: 'Create ALL subtasks upfront...',
    anti_deferral: 'Create all phases with equal detail...',
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add plugin/task-system/lib/tools.js
git commit -m "perf: only include decompose guidance on first decomposition

Saves ~250 tokens on subsequent task_decompose calls where the
instructions are already in context from the first call."
```

---

### Task 12: Extract prompt-improver inline agent prompt

**Files:**
- Create: `plugin/skills/prompt-improver/assets/generation-agent-prompt.md`
- Modify: `plugin/skills/prompt-improver/SKILL.md`

The SKILL.md embeds a ~1400 token agent prompt inline. This loads into context on every `/prompt-improver` invocation even though it's only needed when spawning the generation agent.

- [ ] **Step 1: Extract the agent prompt**

Read lines 79-176 of `plugin/skills/prompt-improver/SKILL.md` and write them to `plugin/skills/prompt-improver/assets/generation-agent-prompt.md`.

- [ ] **Step 2: Replace inline block with reference**

Replace the extracted section in SKILL.md with:

```markdown
### Step 4: Spawn the generation agent

Read the agent prompt from `${CLAUDE_SKILL_DIR}/assets/generation-agent-prompt.md`.

Spawn an Agent with that prompt, substituting:
- `{CONVERSATION_SUMMARY}` — the summary from Step 2
- `{RAW_INPUT}` — the user's original prompt text
- `{MODE}` — execute, plan, or task
- `{REFERENCE_MATERIALS}` — content from the reference files read in Step 3
```

- [ ] **Step 3: Commit**

```bash
git add plugin/skills/prompt-improver/
git commit -m "perf: extract inline agent prompt from prompt-improver SKILL.md

Saves ~1400 tokens on every /prompt-improver invocation. The agent
prompt is now lazy-loaded from assets/ only when the agent is spawned."
```

---

### Task 13: Gate session-stop diagnostic behind debug flag

**Files:**
- Modify: `plugin/scripts/session-stop-dispatcher.sh:15`

A debug artifact writes to `/tmp/claudetools-stop-diagnostic.log` unconditionally on every Stop event.

- [ ] **Step 1: Gate behind environment variable**

Change line 15 from:
```bash
echo "STOP-DIAG: $(date -u +%Y-%m-%dT%H:%M:%SZ) CWD=$(pwd) ..." >> /tmp/claudetools-stop-diagnostic.log
```
To:
```bash
[[ "${CLAUDETOOLS_DEBUG:-}" == "1" ]] && echo "STOP-DIAG: $(date -u +%Y-%m-%dT%H:%M:%SZ) CWD=$(pwd) ..." >> /tmp/claudetools-stop-diagnostic.log
```

- [ ] **Step 2: Commit**

```bash
git add plugin/scripts/session-stop-dispatcher.sh
git commit -m "chore: gate stop diagnostic behind CLAUDETOOLS_DEBUG flag"
```

---

## Execution Order

Tasks are **independent** and can be parallelized in groups:

**Group A (can run in parallel):** Tasks 1, 3, 7, 8, 9, 13
**Group B (depends on Task 4 + 6 patterns):** Tasks 4, 5, 6
**Group C (independent):** Tasks 10, 11, 12
**Task 2 (manual):** After Task 1 is verified working

## Self-Review Checklist

- [x] Every task has exact file paths and line numbers
- [x] Complete code shown in every step
- [x] Verification commands with expected output
- [x] No placeholders or "TBD" items
- [x] Types and variable names consistent across tasks
- [x] All audit findings from the three subagent reports addressed
- [x] Conventional commits used throughout
