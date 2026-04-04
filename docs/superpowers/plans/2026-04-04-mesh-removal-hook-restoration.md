# Mesh Removal + Hook Restoration + srcpilot Full Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the agent-mesh system cleanly, restore the gutted hook dispatchers, apply legitimate fixes from the working tree, fix the `decision=allow exit=2` bug, fully replace the bundled `codebase-pilot` package with the globally-installed `srcpilot` CLI, and sync everything to `plugins/claudetools/`.

**Architecture:** Two parallel tracks. Track 1: fix the working tree — restore the gutted dispatchers from HEAD, then apply surgical mesh-removal on top. Track 2: replace codebase-pilot — move `session-index.sh` to `scripts/`, delete the bundled TypeScript package, update all CLI invocations across skills/rules/assets from `node .../codebase-pilot/dist/cli.js` to `srcpilot`, and surface the new srcpilot-exclusive commands (why, next, ambiguities, budget, cycles, etc.) in the codebase-explorer skill. srcpilot is referenced as a required global install; the plugin handles its absence gracefully.

**Tech Stack:** Bash shell scripts, Claude Code hooks.json, Markdown (skills/rules), git

### srcpilot command mapping (codebase-pilot → srcpilot)

| Old (bundled) | New (global) | Notes |
|---|---|---|
| `node .../cli.js map` | `srcpilot map` | identical |
| `node .../cli.js find-symbol <n>` | `srcpilot find <n>` | alias: find-symbol |
| `node .../cli.js find-usages <n>` | `srcpilot usages <n>` | alias: find-usages |
| `node .../cli.js file-overview <p>` | `srcpilot overview <p>` | alias: file-overview |
| `node .../cli.js related-files <p>` | `srcpilot related <p>` | alias: related-files |
| `node .../cli.js navigate <q>` | `srcpilot navigate <q>` | identical |
| `node .../cli.js dead-code` | `srcpilot dead` | alias: dead-code |
| `node .../cli.js change-impact <s>` | `srcpilot impact <s>` | alias: change-impact |
| `node .../cli.js index-file <p>` | `srcpilot reindex <p>` | alias: index-file |
| `node .../cli.js index` | `srcpilot index` | identical |
| _(new)_ | `srcpilot why <q>` | rank root nodes + owners |
| _(new)_ | `srcpilot next <q>` | rank what to open next |
| _(new)_ | `srcpilot ambiguities` | duplicate names, split owners |
| _(new)_ | `srcpilot budget` | files by import frequency (context-budget) |
| _(new)_ | `srcpilot exports` | exported symbols (api-surface) |
| _(new)_ | `srcpilot cycles` | circular imports |
| _(new)_ | `srcpilot implementations <s>` | competing implementations |

---

## File Map

| File | Action | Reason |
|------|--------|--------|
| `plugin/scripts/pre-tool-dispatcher.sh` | Restore from HEAD | Gutted by agent — remove only non-mesh parts |
| `plugin/scripts/post-tool-dispatcher.sh` | Restore from HEAD | Gutted by agent — all post-tool hooks removed incorrectly |
| `plugin/scripts/pre-bash-gate.sh` | Restore from HEAD | Gutted by agent — ai-safety/unasked-restructure/deploy-loop removed |
| `plugin/hooks/hooks.json` | Restore from HEAD, remove 4 mesh entries, update session-index.sh paths | Gutted + mesh + path migration |
| `plugin/codebase-pilot/scripts/session-index.sh` | Move → `plugin/scripts/session-index.sh`, remove mesh block | Path migration + mesh removal |
| `plugin/scripts/inject-prompt-context.sh` | Apply working tree change | Remove mesh inbox/heartbeat |
| `plugin/scripts/track-file-edits.sh` | Apply working tree change | Remove mesh file tracking |
| `plugin/scripts/session-start-dispatcher.sh` | Remove mesh step, update session-index.sh path | Mesh removal + path migration |
| `plugin/scripts/pre-edit-gate.sh` | Apply working tree change | Remove mesh-lock validator |
| `plugin/scripts/failure-pattern-detector.sh` | Apply working tree change | Add benign patterns: rg missing, worktree path |
| `plugin/scripts/validators/session-stop-gate.sh` | Apply working tree change | Downgrade block→warn |
| `plugin/agent-mesh/cli.js` | Delete | Mesh retired |
| `plugin/scripts/mesh-lifecycle.sh` | Delete | Mesh retired |
| `plugin/scripts/validators/mesh-lock.sh` | Delete | Mesh retired |
| `plugin/codebase-pilot/` (entire dir) | Delete (src, dist, node_modules, scripts, package.json, .codeindex) | Replaced by global srcpilot |
| `plugin/skills/codebase-explorer/SKILL.md` | Rewrite CLI section | Replace bundled CLI with srcpilot, add new commands |
| `plugin/skills/task-manager/SKILL.md` | Update 3 lines | codebase-pilot CLI → srcpilot |
| `plugin/skills/task-manager/references/enrichment-agent.md` | Update CLI block | codebase-pilot CLI → srcpilot |
| `plugin/skills/task-manager/references/workflow-patterns.md` | Update MCP tool refs | Replace with srcpilot CLI commands |
| `plugin/skills/prompt-improver/assets/generation-agent-prompt.md` | Update CLI call | codebase-pilot → srcpilot |
| `plugin/rules/codebase-navigation.md` | Extend command table | Add why, next, ambiguities, budget, exports, cycles |
| `plugin/assets/subagent-context.md` | Update if present | Any codebase-pilot refs → srcpilot |
| `plugin/.claude-plugin/plugin.json` | Update description | Mention srcpilot as required global install |
| `plugins/claudetools/` | rsync from `plugin/` | Sync published artifacts |

---

## Task 1: Pull latest from remote

**Files:** none (git operations only)

- [ ] **Step 1: Pull remote main (get 5.0.3)**

```bash
cd /home/maverick/projects/marketplace-dev
git pull origin main
```

Expected: "1 file changed" (the auto-bump 5.0.2→5.0.3 commit).

- [ ] **Step 2: Verify local HEAD matches remote**

```bash
git log --oneline -3
```

Expected: top commit is `chore: auto-bump claudetools@5.0.3`.

---

## Task 2: Restore gutted dispatchers from HEAD

The working tree has `pre-tool-dispatcher.sh`, `post-tool-dispatcher.sh`, and `pre-bash-gate.sh` gutted. Restore them to the committed version. We will apply targeted mesh-removal in a later task.

- [ ] **Step 1: Restore pre-tool-dispatcher.sh**

```bash
git checkout HEAD -- plugin/scripts/pre-tool-dispatcher.sh
```

- [ ] **Step 2: Restore post-tool-dispatcher.sh**

```bash
git checkout HEAD -- plugin/scripts/post-tool-dispatcher.sh
```

- [ ] **Step 3: Restore pre-bash-gate.sh**

```bash
git checkout HEAD -- plugin/scripts/pre-bash-gate.sh
```

- [ ] **Step 4: Verify the three files are now clean**

```bash
git diff HEAD plugin/scripts/pre-tool-dispatcher.sh plugin/scripts/post-tool-dispatcher.sh plugin/scripts/pre-bash-gate.sh
```

Expected: no output (clean).

---

## Task 3: Restore hooks.json from HEAD

The working tree hooks.json dropped 8 hook event types. Restore it first, then we'll remove only the 4 mesh-lifecycle entries cleanly.

- [ ] **Step 1: Restore hooks.json**

```bash
git checkout HEAD -- plugin/hooks/hooks.json
```

- [ ] **Step 2: Verify it's clean**

```bash
git diff HEAD plugin/hooks/hooks.json
```

Expected: no output.

---

## Task 4: Remove mesh from hooks.json

The committed hooks.json has 4 `mesh-lifecycle.sh` entries. Remove each one precisely. The SubagentStop entry has two hooks — remove only the mesh one, keep `verify-subagent-independently.sh`. SubagentStart has two — remove only mesh, keep `codebase-pilot/scripts/session-index.sh`. SessionEnd has three — remove only mesh, keep the other two. WorktreeCreate has three — remove only mesh, keep `session-index.sh` and `track-worktree-session.sh`.

- [ ] **Step 1: Edit `plugin/hooks/hooks.json` — remove all 4 mesh-lifecycle blocks**

The current committed hooks.json has these mesh entries (remove each entire hook object, leaving the other hooks in each event intact):

In `SubagentStop` — remove:
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mesh-lifecycle.sh deregister",
            "timeout": 5
          }
        ]
      },
```

In `SubagentStart` — remove:
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mesh-lifecycle.sh register",
            "timeout": 5
          }
        ]
      },
```

In `SessionEnd` — remove:
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mesh-lifecycle.sh deregister",
            "timeout": 5
          }
        ]
      },
```

In `WorktreeCreate` — remove:
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/mesh-lifecycle.sh register",
            "timeout": 5
          }
        ]
      },
```

- [ ] **Step 2: Verify no mesh-lifecycle references remain**

```bash
grep "mesh" plugin/hooks/hooks.json
```

Expected: no output.

- [ ] **Step 3: Validate JSON is still valid**

```bash
python3 -m json.tool plugin/hooks/hooks.json > /dev/null && echo "valid"
```

Expected: `valid`

---

## Task 5: Remove mesh from session-start-dispatcher.sh

The committed version calls `mesh-lifecycle.sh register` (step 4) and `track-worktree-session.sh` (step 5). Remove ONLY the mesh step; keep `track-worktree-session.sh` (it records crash-recovery metadata independently of mesh).

- [ ] **Step 1: Edit `plugin/scripts/session-start-dispatcher.sh`**

Find and remove these two lines (steps 4 and the helper call):
```bash
# 4. Register this session with the agent mesh
run_session_hook_with_arg "$SCRIPT_DIR/mesh-lifecycle.sh" "register"
```

Then renumber the remaining steps so they read sequentially. The result should be (using the updated session-index.sh path from Task 15):
```bash
# 1. srcpilot session index
run_session_hook "$SCRIPT_DIR/session-index.sh"

# 2. Inject session context into the conversation
run_session_hook "$SCRIPT_DIR/inject-session-context.sh"

# 3. Detect stale documentation
run_session_hook "$SCRIPT_DIR/doc-stale-detector.sh"

# 4. Track worktree session
run_session_hook "$SCRIPT_DIR/track-worktree-session.sh"

# 5. Configure statusline
run_session_hook "$SCRIPT_DIR/statusline/configure.sh"
```

Note: Task 15 handles the path migration of session-index.sh; Task 20 adds ensure-srcpilot.sh as step 0.

- [ ] **Step 2: Verify no mesh references remain**

```bash
grep "mesh" plugin/scripts/session-start-dispatcher.sh
```

Expected: no output.

---

## Task 6: Remove mesh from session-index.sh

`codebase-pilot/scripts/session-index.sh` has an agent-mesh registration block at the bottom (lines ~289–312). Remove it. The surrounding srcpilot context output and memory injection should remain intact.

- [ ] **Step 1: Locate the mesh block in session-index.sh**

```bash
grep -n "MESH_CLI\|agent-mesh" plugin/codebase-pilot/scripts/session-index.sh
```

Expected: lines 290, 291, 294, 306, 309 (the MESH_CLI block).

- [ ] **Step 2: Edit `plugin/codebase-pilot/scripts/session-index.sh`** — remove this entire block (from `# --- Agent mesh registration ---` to the closing `fi`):

```bash
# --- Agent mesh registration ---
MESH_CLI="$PLUGIN_ROOT/agent-mesh/cli.js"
if [[ -f "$MESH_CLI" ]]; then
  AGENT_NAME="${AGENT_MESH_NAME:-agent-${SESSION_ID}}"
  BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
  node "$MESH_CLI" register \
    --id "$SESSION_ID" \
    --name "$AGENT_NAME" \
    --worktree "$PROJECT_ROOT" \
    --branch "$BRANCH" \
    --pid "$PPID" 2>/dev/null || true

  # NOTE: Deregistration is handled by session-end-dispatcher.sh (SessionEnd hook).
  # Do NOT add an EXIT/INT/TERM trap here — this script runs as a short-lived hook
  # process, so traps fire immediately when the script exits, not when the Claude
  # session ends. That was the original bug that broke the entire mesh.

  OTHERS=$(node "$MESH_CLI" list --exclude "$SESSION_ID" --brief 2>/dev/null || true)
  if [[ -n "$OTHERS" ]]; then
    echo ""
    echo "[agent-mesh] Other agents active in this repo:"
    echo "$OTHERS"
  fi
fi
```

- [ ] **Step 3: Verify no mesh references remain**

```bash
grep "mesh\|MESH_CLI" plugin/codebase-pilot/scripts/session-index.sh
```

Expected: no output.

---

## Task 7: Remove mesh from inject-prompt-context.sh

The working tree already has this change. Apply it by accepting the working tree version.

- [ ] **Step 1: Verify working tree diff is only the mesh block removal**

```bash
git diff HEAD plugin/scripts/inject-prompt-context.sh
```

Expected: diff shows only the `--- Agent mesh inbox` block being removed (10 lines, no other changes).

- [ ] **Step 2: If diff is clean, keep as-is. If it has other unintended changes, restore from HEAD and re-apply manually**

The block to remove from inject-prompt-context.sh is:
```bash
# --- Agent mesh inbox (only if messages waiting) ---
MESH_CLI="$(dirname "$(dirname "$0")")/agent-mesh/cli.js"
if [[ -f "$MESH_CLI" ]]; then
  MESSAGES=$(node "$MESH_CLI" inbox --id "$SESSION_ID" --ack 2>/dev/null) || true
  if [[ -n "$MESSAGES" ]]; then
    echo "[mesh] $MESSAGES"
  fi
  { node "$MESH_CLI" heartbeat --id "$SESSION_ID" 2>/dev/null || true; } &
fi
```

- [ ] **Step 3: Verify no mesh references remain**

```bash
grep "mesh\|MESH_CLI" plugin/scripts/inject-prompt-context.sh
```

Expected: no output.

---

## Task 8: Remove mesh from pre-edit-gate.sh and track-file-edits.sh

Both have small mesh removals already in the working tree.

- [ ] **Step 1: Verify pre-edit-gate.sh diff**

```bash
git diff HEAD plugin/scripts/pre-edit-gate.sh
```

Expected: only removes `source "$SCRIPT_DIR/validators/mesh-lock.sh"` and the `run_pretool_validator "mesh-lock-check" validate_mesh_lock` call. Nothing else.

If clean, keep. If contaminated, restore and reapply:
```bash
git checkout HEAD -- plugin/scripts/pre-edit-gate.sh
```
Then remove the two mesh lines manually.

- [ ] **Step 2: Verify track-file-edits.sh diff**

```bash
git diff HEAD plugin/scripts/track-file-edits.sh
```

Expected: only removes the `--- Agent mesh file tracking ---` block (7 lines). Nothing else.

If clean, keep. If contaminated, restore and reapply.

---

## Task 9: Delete mesh files

- [ ] **Step 1: Delete the three mesh files**

```bash
rm plugin/agent-mesh/cli.js
rm plugin/scripts/mesh-lifecycle.sh
rm plugin/scripts/validators/mesh-lock.sh
```

- [ ] **Step 2: Check if agent-mesh/ directory is now empty**

```bash
ls plugin/agent-mesh/ 2>/dev/null || echo "directory empty or gone"
```

If the directory is empty (or has only non-mesh files), remove it:
```bash
rmdir plugin/agent-mesh/ 2>/dev/null || ls plugin/agent-mesh/
```

- [ ] **Step 3: Confirm no remaining references to deleted files**

```bash
grep -r "mesh-lifecycle\|mesh-lock\|agent-mesh/cli" plugin/ --include="*.sh" --include="*.json" -l
```

Expected: no output.

---

## Task 10: Apply failure-pattern-detector.sh fixes

The working tree adds two legitimate benign patterns. Verify and keep.

- [ ] **Step 1: Verify the diff is only additive benign patterns**

```bash
git diff HEAD plugin/scripts/failure-pattern-detector.sh
```

Expected: two small additions:
- `echo "$ERROR" | grep -qiE 'ENOENT.*posix_spawn|posix_spawn.*rg|no such file.*rg\b|rg.*not found' && return 0` (for Grep and Glob)
- `echo "$ERROR" | grep -qiE 'Path.*does not exist|worktree.*does not exist' && return 0` (for Bash)

If the diff has those and nothing else, keep as-is.

---

## Task 11: Apply session-stop-gate.sh warn downgrade

The working tree downgrades the stop-gate from hard-block (exit 2) to warning (exit 1) for uncommitted changes on main, and removes the now-defunct mesh-active check.

- [ ] **Step 1: Review the diff**

```bash
git diff HEAD plugin/scripts/validators/session-stop-gate.sh
```

The key change: `return 2` → `return 1` and `record_hook_outcome ... "block"` → `record_hook_outcome ... "warn"` in two places. Also removes the mesh-CLI agents_active check block.

- [ ] **Step 2: Keep the change (it was intentional)**

No action needed — working tree version is correct.

---

## Task 12: Investigate and fix `decision=allow exit=2` bug

In production logs (`agent=main`, not test), there are entries where a hook logs `decision=allow` but exits with code 2. Exit 2 = hard block in Claude Code, so this silently blocks operations while logging them as allowed.

- [ ] **Step 1: Find all hooks that could produce exit=2 after logging "allow"**

```bash
grep -rn "return 2\|exit 2" plugin/scripts/ --include="*.sh" | grep -v "#\|test\|mesh\|dangerous\|sensitive" | head -30
```

- [ ] **Step 2: Check if set -euo pipefail + a failing subshell could cause it**

Any script with `set -euo pipefail` that calls a command exiting 2 after its own `record_hook_outcome ... allow` call will log "allow" but exit 2. Search for patterns:

```bash
grep -rn "set -euo pipefail" plugin/scripts/ --include="*.sh" -l
```

For each file, check whether any command after the "allow" path could exit 2.

- [ ] **Step 3: Check inject-prompt-context.sh specifically**

`tool=none` entries in the logs correspond to UserPromptSubmit (inject-prompt-context.sh). With the mesh inbox block now removed, this likely fixes the March 31 rapid-fire entries (mesh CLI was probably failing and propagating exit 2 via set -e interactions).

Verify the current script exits cleanly:

```bash
echo '{"session_id":"test","hook_event_name":"UserPromptSubmit"}' | bash plugin/scripts/inject-prompt-context.sh
echo "exit: $?"
```

Expected: exit 0, some context output or nothing.

- [ ] **Step 4: Check session-stop-dispatcher.sh**

```bash
cat plugin/scripts/session-stop-dispatcher.sh | grep -n "exit\|return"
```

Look for any path that exits 2 after allowing.

- [ ] **Step 5: Fix any confirmed bug**

If a script is found where exit 2 leaks through after "allow" logging, fix by adding `|| true` after the offending command or restructuring the exit path. The fix depends on what's found — update this step when the cause is identified.

- [ ] **Step 6: Add a smoke test for UserPromptSubmit**

```bash
echo '{"session_id":"test-$$","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}' | bash plugin/scripts/inject-prompt-context.sh > /tmp/test-inject-out.txt 2>&1
EXIT_CODE=$?
echo "Exit: $EXIT_CODE"
cat /tmp/test-inject-out.txt | head -5
```

Expected: `Exit: 0`

---

## Task 13: Sync to plugins/claudetools/

- [ ] **Step 1: Run the sync**

```bash
rsync -a --delete \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='logs/' \
  /home/maverick/projects/marketplace-dev/plugin/ \
  /home/maverick/projects/marketplace-dev/plugins/claudetools/
```

- [ ] **Step 2: Verify the sync removed mesh files from plugins/claudetools/**

```bash
ls plugins/claudetools/agent-mesh/ 2>/dev/null && echo "PROBLEM: mesh dir still present" || echo "clean"
grep "mesh-lifecycle" plugins/claudetools/hooks/hooks.json && echo "PROBLEM: mesh in hooks.json" || echo "clean"
```

Expected: both lines print `clean`.

- [ ] **Step 3: Verify key restored files match**

```bash
diff plugin/scripts/pre-tool-dispatcher.sh plugins/claudetools/scripts/pre-tool-dispatcher.sh
diff plugin/scripts/post-tool-dispatcher.sh plugins/claudetools/scripts/post-tool-dispatcher.sh
diff plugin/hooks/hooks.json plugins/claudetools/hooks/hooks.json
```

Expected: no output (identical).

---

## Task 14: Commit and push

- [ ] **Step 1: Review final diff**

```bash
git diff --stat HEAD
git status
```

Confirm: no files from `plugins/claudetools/` in the diff (rsync should have made them match plugin/ which is tracked). Confirm mesh files are deleted. Confirm restored dispatchers.

- [ ] **Step 2: Stage all changes**

```bash
git add plugin/ plugins/claudetools/
git status
```

Verify staged changes look right: mesh files deleted, dispatchers restored, hooks.json with mesh removed, benign fixes applied.

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: remove agent-mesh, restore hook dispatchers, fix benign failure patterns

- Remove agent-mesh system (cli.js, mesh-lifecycle.sh, validators/mesh-lock.sh)
- Remove all mesh-lifecycle hook entries from hooks.json
- Remove mesh registration from session-index.sh, inject-prompt-context.sh,
  track-file-edits.sh, session-start-dispatcher.sh, pre-edit-gate.sh
- Restore pre-tool-dispatcher.sh: re-add enforce-read-efficiency,
  enforce-memory-preferences, pre-edit-gate, enforce-native-task-hygiene,
  enforce-team-usage, intercept-grep validators (wrongly removed by prior agent)
- Restore post-tool-dispatcher.sh: re-add all post-tool hooks (wrongly removed)
- Restore pre-bash-gate.sh: re-add ai-safety, unasked-restructure,
  deploy-loop-detector validators (wrongly removed)
- Restore hooks.json: re-add TaskCompleted, SubagentStop, TeammateIdle, Stop,
  PostToolUseFailure, Notification, ConfigChange, WorktreeCreate hooks
- failure-pattern-detector.sh: add rg-missing and worktree-path benign patterns
- session-stop-gate.sh: downgrade uncommitted-changes block to warning
- Sync plugin/ to plugins/claudetools/
EOF
)"
```

- [ ] **Step 4: Push to trigger auto-version**

```bash
git push origin main
```

Expected: CI runs, auto-bumps version, publishes to marketplace.

---

---

## Task 15: Move session-index.sh out of codebase-pilot/

`codebase-pilot/scripts/session-index.sh` is the primary hook that indexes the project and injects context. Move it to `scripts/` now that codebase-pilot is being deleted.

**Files:**
- Move: `plugin/codebase-pilot/scripts/session-index.sh` → `plugin/scripts/session-index.sh`
- Modify: `plugin/hooks/hooks.json` — update 3 entries
- Modify: `plugin/scripts/session-start-dispatcher.sh` — update 1 path

- [ ] **Step 1: Copy session-index.sh to scripts/**

```bash
cp plugin/codebase-pilot/scripts/session-index.sh plugin/scripts/session-index.sh
```

(The file was already edited in Task 6 to remove the mesh block. Verify the mesh block is gone in the copy:)

```bash
grep "MESH_CLI\|agent-mesh" plugin/scripts/session-index.sh
```

Expected: no output.

- [ ] **Step 2: Update hooks.json — replace codebase-pilot path with scripts/ path**

In `plugin/hooks/hooks.json`, find every occurrence of:
```json
"${CLAUDE_PLUGIN_ROOT}/codebase-pilot/scripts/session-index.sh"
```
and replace with:
```json
"${CLAUDE_PLUGIN_ROOT}/scripts/session-index.sh"
```

There are 3 occurrences: SubagentStart, ConfigChange, WorktreeCreate.

- [ ] **Step 3: Update session-start-dispatcher.sh — replace codebase-pilot path**

In `plugin/scripts/session-start-dispatcher.sh`, change:
```bash
run_session_hook "$PLUGIN_ROOT/codebase-pilot/scripts/session-index.sh"
```
to:
```bash
run_session_hook "$SCRIPT_DIR/session-index.sh"
```

- [ ] **Step 4: Remove `run_session_hook_with_arg` helper if now unused**

After removing mesh-lifecycle.sh from session-start-dispatcher.sh (Task 5), `run_session_hook_with_arg` is no longer called. Remove it:

```bash
grep "run_session_hook_with_arg" plugin/scripts/session-start-dispatcher.sh
```

If it appears only in the function definition (not called), remove the whole function definition block.

- [ ] **Step 5: Verify hooks.json has no codebase-pilot paths remaining**

```bash
grep "codebase-pilot" plugin/hooks/hooks.json
```

Expected: no output.

- [ ] **Step 6: Verify session-start-dispatcher.sh has no codebase-pilot paths**

```bash
grep "codebase-pilot" plugin/scripts/session-start-dispatcher.sh
```

Expected: no output.

---

## Task 16: Delete codebase-pilot/ directory

With session-index.sh moved, the entire bundled codebase-pilot package is now dead code.

**Files:** Delete `plugin/codebase-pilot/` entirely (except confirm nothing else references it first)

- [ ] **Step 1: Confirm no remaining references to codebase-pilot path**

```bash
grep -r "codebase-pilot" plugin/ --include="*.sh" --include="*.json" -l | grep -v "node_modules\|logs"
```

Expected: no output (all path references updated in previous tasks).

- [ ] **Step 2: Delete the directory**

```bash
rm -rf plugin/codebase-pilot/
```

- [ ] **Step 3: Verify gone**

```bash
ls plugin/codebase-pilot 2>/dev/null && echo "PROBLEM: still exists" || echo "clean"
```

Expected: `clean`

---

## Task 17: Update codebase-explorer SKILL.md

Replace all `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js` invocations with `srcpilot`, add the new srcpilot-exclusive commands as new modes, and update the intro description.

**File:** `plugin/skills/codebase-explorer/SKILL.md`

- [ ] **Step 1: Replace CLI path and intro description**

Change the opening description and CLI path line:

From:
```markdown
Structured codebase navigation using the codebase-pilot CLI. This skill wraps the CLI into workflow modes that chain commands for deeper understanding.

The CLI path: `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js`
```
To:
```markdown
Structured codebase navigation using the srcpilot CLI (globally installed: `npm install -g srcpilot`). This skill wraps the CLI into workflow modes that chain commands for deeper understanding.
```

- [ ] **Step 2: Replace all CLI invocations in the mode sections**

Find and replace every occurrence of `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js` with `srcpilot`. The command names stay the same (srcpilot supports them as aliases):

| Old | New |
|-----|-----|
| `node .../cli.js map` | `srcpilot map` |
| `node .../cli.js find-symbol "$ARGUMENTS"` | `srcpilot find "$ARGUMENTS"` |
| `node .../cli.js find-symbol "$ARGUMENTS" --kind function` | `srcpilot find "$ARGUMENTS" --kind function` |
| `node .../cli.js file-overview "$ARGUMENTS"` | `srcpilot overview "$ARGUMENTS"` |
| `node .../cli.js related-files "$ARGUMENTS"` | `srcpilot related "$ARGUMENTS"` |
| `node .../cli.js find-usages "$ARGUMENTS"` | `srcpilot usages "$ARGUMENTS"` |
| `node .../cli.js navigate "$ARGUMENTS"` | `srcpilot navigate "$ARGUMENTS"` |
| `node .../cli.js dead-code` | `srcpilot dead` |
| `node .../cli.js change-impact "handleAuth"` | `srcpilot impact "handleAuth"` |
| `node .../cli.js index-file "<path>"` | `srcpilot reindex "<path>"` |
| `node .../cli.js index` | `srcpilot index` |

Also update the Mode Selection table to use `srcpilot` names, and fix the "Handler function (located via codebase-pilot find-symbol)" text to read "located via `srcpilot find`".

- [ ] **Step 3: Add new srcpilot-exclusive modes to the Mode Selection table**

Add these rows to the mode table:

```markdown
| "Why is this file important?" / "What owns this logic?" | **why** | `srcpilot why <query>` |
| "What should I open next?" / "Where is this pattern used?" | **next** | `srcpilot next <query>` |
| "Are there duplicate implementations?" / "Name conflicts?" | **ambiguities** | `srcpilot ambiguities` |
| "What are the most-imported files?" / "Context budget" | **budget** | `srcpilot budget` |
| "What does this module export?" / "API surface" | **exports** | `srcpilot exports` |
| "Are there circular imports?" | **cycles** | `srcpilot cycles` |
| "Show all implementations of X" | **implementations** | `srcpilot implementations <symbol>` |
```

- [ ] **Step 4: Add sections for the new modes**

After the existing mode sections, add:

```markdown
## Mode: why

Rank the most likely root nodes and owners for a concept — useful for tracing architectural responsibility.

```bash
srcpilot why "<query>"
```

**When to use:** "Why does auth fail here?", "What owns the payment logic?", "Root cause of this error pattern"

## Mode: next

Rank what file to open next based on a query — combines symbol matching, import frequency, and structural centrality.

```bash
srcpilot next "<query>"
```

**When to use:** "What should I read after looking at this file?", "Where is this pattern most used?"

## Mode: ambiguities

Find symbols with duplicate names (potential confusion) and symbols split across multiple owners (refactor candidates).

```bash
srcpilot ambiguities
srcpilot ambiguities "<query>"  # filter to specific area
```

**When to use:** "Are there naming conflicts?", "What needs to be disambiguated before refactoring?"

## Mode: budget

Rank files by import frequency — the most-imported files are the ones that matter most for context window decisions.

```bash
srcpilot budget
```

**When to use:** "What are the core files I need to understand?", "Which files should I read first for context?"

## Mode: exports

List all exported symbols in the project — the public API surface.

```bash
srcpilot exports
```

**When to use:** "What does this module expose?", "Show me the public API"

## Mode: cycles

Find circular import chains — useful before large refactors.

```bash
srcpilot cycles
```

**When to use:** "Are there circular dependencies?", "What will break if I split this module?"

## Mode: implementations

Show all competing implementations of a symbol — catches duplication across the codebase.

```bash
srcpilot implementations "<symbol>"
```

**When to use:** "Are there multiple implementations of handleAuth?", "Show me all versions of this function"
```

- [ ] **Step 5: Update the Context Awareness section**

Change:
```markdown
- If files were recently edited, run `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js index-file "<path>"` to incrementally re-index changed files
```
To:
```markdown
- If files were recently edited, run `srcpilot reindex "<path>"` to incrementally re-index changed files
```

- [ ] **Step 6: Update the Reindex section**

Change:
```markdown
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js index
```
and:
```markdown
node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js index-file <path>
```
To:
```markdown
srcpilot index
```
and:
```markdown
srcpilot reindex <path>
```

- [ ] **Step 7: Verify no codebase-pilot references remain**

```bash
grep -n "codebase.pilot\|dist/cli" plugin/skills/codebase-explorer/SKILL.md
```

Expected: no output.

---

## Task 18: Update rules/codebase-navigation.md

The rule already uses `srcpilot` — extend it with the 7 new commands.

**File:** `plugin/rules/codebase-navigation.md`

- [ ] **Step 1: Add new commands to the command table**

After the existing 6-command table, add:

```markdown
| `why` | `srcpilot why "<query>"` | Rank root nodes and likely owners for a concept |
| `next` | `srcpilot next "<query>"` | Rank what to open next (import frequency + centrality) |
| `ambiguities` | `srcpilot ambiguities` | Find duplicate symbol names and split ownership |
| `budget` | `srcpilot budget` | Rank files by import frequency (core context budget) |
| `exports` | `srcpilot exports` | List all exported symbols (API surface) |
| `cycles` | `srcpilot cycles` | Detect circular imports |
| `implementations` | `srcpilot implementations "<symbol>"` | Find competing implementations |
```

- [ ] **Step 2: Extend "When to Use Which Command"**

Add after the existing 4 bullets:
```markdown
- Use `why` when you need to understand architectural ownership or trace root causes
- Use `next` when navigating an unfamiliar area and unsure what to read after current file
- Use `budget` to prioritize which files to load into context for a large task
- Use `cycles` before a refactor involving module splits
- Use `ambiguities` when renaming to check for name conflicts first
```

- [ ] **Step 3: Verify**

```bash
grep "codebase-pilot\|dist/cli" plugin/rules/codebase-navigation.md
```

Expected: no output.

---

## Task 19: Update skills/task-manager and prompt-improver

Three files reference the bundled CLI in inline examples.

**Files:**
- `plugin/skills/task-manager/SKILL.md`
- `plugin/skills/task-manager/references/enrichment-agent.md`
- `plugin/skills/task-manager/references/workflow-patterns.md`
- `plugin/skills/prompt-improver/assets/generation-agent-prompt.md`

- [ ] **Step 1: Update task-manager/SKILL.md**

Find 3 occurrences of `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js` and replace with `srcpilot`:

From:
```markdown
2. **Explore the codebase** using codebase-pilot:
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js find-symbol "<relevant-name>"
   node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js related-files "<entry-point>"
```
To:
```markdown
2. **Explore the codebase** using srcpilot:
   srcpilot map
   srcpilot find "<relevant-name>"
   srcpilot related "<entry-point>"
```

Also change the three inline references to "codebase-pilot CLI" → "srcpilot CLI".

- [ ] **Step 2: Update enrichment-agent.md**

Find and replace the CLI instruction block:
```markdown
> 3. **Use codebase-pilot CLI for file discovery.** Run via Bash: `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js <command>`. Commands: `map` (project overview), `find-symbol "<name>"` (locate functions/classes by name), `file-overview "<path>"` (list symbols in a file), `related-files "<path>"` (find imports/dependents). Use REAL paths from these commands — do not invent file paths. Run `find-symbol` and `file-overview` to verify any paths before including them in task content.
```
To:
```markdown
> 3. **Use srcpilot CLI for file discovery.** Commands: `srcpilot map` (project overview), `srcpilot find "<name>"` (locate functions/classes by name), `srcpilot overview "<path>"` (list symbols in a file), `srcpilot related "<path>"` (find imports/dependents). Use REAL paths from these commands — do not invent file paths. Run `find` and `overview` to verify any paths before including them in task content.
```

Also update the `> **Codebase context (from codebase-pilot):**` header to `> **Codebase context (from srcpilot):**` and any "codebase-pilot tools" references.

- [ ] **Step 3: Update workflow-patterns.md**

Replace:
```markdown
1. **Gather codebase context first**: Use codebase-pilot MCP tools (project_map, find_symbol, file_overview, related_files) to discover real file paths and understand the project structure before writing task content.
```
With:
```markdown
1. **Gather codebase context first**: Use srcpilot CLI (`srcpilot map`, `srcpilot find`, `srcpilot overview`, `srcpilot related`) to discover real file paths and understand the project structure before writing task content.
```

Also update any other "codebase-pilot tools" or "codebase-pilot MCP" refs in the file.

- [ ] **Step 4: Update generation-agent-prompt.md**

Find:
```markdown
Then use the codebase-pilot CLI to gather structural context: run `node ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/dist/cli.js map` for the project overview. For any file paths or function/class names mentioned in the raw input, run `node .../cli.js find-symbol "<name>"` to locate them and `node .../cli.js file-overview "<path>"` to understand their structure. Use REAL paths from these commands in your output — do not invent file paths.
```
Replace with:
```markdown
Then use the srcpilot CLI to gather structural context: run `srcpilot map` for the project overview. For any file paths or function/class names mentioned in the raw input, run `srcpilot find "<name>"` to locate them and `srcpilot overview "<path>"` to understand their structure. Use REAL paths from these commands in your output — do not invent file paths.
```

- [ ] **Step 5: Verify all four files are clean**

```bash
grep -rn "codebase.pilot\|dist/cli" \
  plugin/skills/task-manager/SKILL.md \
  plugin/skills/task-manager/references/enrichment-agent.md \
  plugin/skills/task-manager/references/workflow-patterns.md \
  plugin/skills/prompt-improver/assets/generation-agent-prompt.md
```

Expected: no output.

---

## Task 20: Update plugin.json description and ensure-srcpilot setup

Make the plugin's manifest and session-start clearly communicate that srcpilot is required, and add a one-time auto-install if it's missing.

**Files:**
- `plugin/.claude-plugin/plugin.json`
- `plugin/scripts/ensure-srcpilot.sh` (new)
- `plugin/scripts/session-start-dispatcher.sh`

- [ ] **Step 1: Update plugin.json description**

Edit `plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "claudetools",
  "version": "5.0.0",
  "description": "Universal guardrail and quality system for Claude Code -- adaptive hooks, self-learning metrics, skills for code, research, writing, and data analysis. Requires srcpilot for codebase navigation (auto-installed on first session). Zero config.",
  ...
}
```

- [ ] **Step 2: Create `plugin/scripts/ensure-srcpilot.sh`**

```bash
#!/usr/bin/env bash
# ensure-srcpilot.sh — One-time setup: install srcpilot globally if missing.
# Writes a marker file after successful install to avoid re-checking every session.
# Always exits 0 — never blocks session start.

set -euo pipefail
source "$(dirname "$0")/hook-log.sh" 2>/dev/null || true

MARKER="$HOME/.claudetools-srcpilot-installed"

# Already confirmed installed this machine — skip
[[ -f "$MARKER" ]] && exit 0

# Already available globally — just mark and exit
if command -v srcpilot &>/dev/null; then
  touch "$MARKER"
  exit 0
fi

# Not installed — try to install via npm
hook_log "ensure-srcpilot: srcpilot not found, installing via npm..." 2>/dev/null || true
echo "[claudetools] Installing srcpilot (codebase navigator)..."

if command -v npm &>/dev/null; then
  if npm install -g srcpilot 2>/dev/null; then
    touch "$MARKER"
    echo "[claudetools] srcpilot installed successfully. Run 'srcpilot index' in your project to build the index."
    hook_log "ensure-srcpilot: installed successfully" 2>/dev/null || true
  else
    echo "[claudetools] srcpilot install failed. Install manually: npm install -g srcpilot"
    hook_log "ensure-srcpilot: npm install failed" 2>/dev/null || true
  fi
else
  echo "[claudetools] npm not found — install srcpilot manually: npm install -g srcpilot"
  hook_log "ensure-srcpilot: npm not available" 2>/dev/null || true
fi

exit 0
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x plugin/scripts/ensure-srcpilot.sh
```

- [ ] **Step 4: Add to session-start-dispatcher.sh as step 1 (before everything else)**

In `plugin/scripts/session-start-dispatcher.sh`, add as the first step:

```bash
# 0. Ensure srcpilot is installed (one-time, no-op if already present)
run_session_hook "$SCRIPT_DIR/ensure-srcpilot.sh"
```

Renumber all subsequent steps (1→2, 2→3, etc.).

- [ ] **Step 5: Smoke test ensure-srcpilot.sh**

```bash
# Temporarily remove the marker to force a re-check
mv ~/.claudetools-srcpilot-installed ~/.claudetools-srcpilot-installed.bak 2>/dev/null || true

echo '{"session_id":"test","hook_event_name":"SessionStart"}' | bash plugin/scripts/ensure-srcpilot.sh
echo "Exit: $?"

# Restore marker
mv ~/.claudetools-srcpilot-installed.bak ~/.claudetools-srcpilot-installed 2>/dev/null || true
```

Expected: `Exit: 0`, no error output (srcpilot already installed, so it just touches the marker).

---

## Task 21: Final verification sweep

- [ ] **Step 1: Confirm zero codebase-pilot references remain across the whole plugin/**

```bash
grep -rn "codebase.pilot\|codebase-pilot\|dist/cli" plugin/ \
  --include="*.sh" --include="*.json" --include="*.md" \
  --exclude-dir=node_modules --exclude-dir=logs \
  | grep -v "CHANGELOG\|plugins-guide\|hooks-guide"
```

The only acceptable remaining references are in `skills/claude-code-guide/references/` (historical docs) and CHANGELOG.md. Everything else must be clean.

- [ ] **Step 2: Confirm no mesh references remain**

```bash
grep -rn "agent-mesh\|mesh-lifecycle\|mesh-lock\|MESH_CLI" plugin/ \
  --include="*.sh" --include="*.json" --include="*.md" \
  --exclude-dir=node_modules --exclude-dir=logs
```

Expected: no output.

- [ ] **Step 3: Verify srcpilot works end-to-end in this project**

```bash
cd /home/maverick/projects/marketplace-dev
srcpilot find "validate_blind_edit"
```

Expected: output showing `plugin/scripts/validators/blind-edit.sh` with a line number.

```bash
srcpilot map
```

Expected: project overview with file counts.

- [ ] **Step 4: Verify hooks.json is valid JSON with expected event types**

```bash
python3 -c "
import json
with open('plugin/hooks/hooks.json') as f:
    h = json.load(f)
events = list(h['hooks'].keys())
print('Events:', events)
expected = ['PreToolUse','PostToolUse','TaskCompleted','SubagentStop','TeammateIdle',
            'Stop','SessionStart','SubagentStart','SessionEnd','UserPromptSubmit',
            'PermissionRequest','PostToolUseFailure','PreCompact','PostCompact',
            'Notification','ConfigChange','WorktreeCreate']
missing = [e for e in expected if e not in events]
print('Missing:', missing or 'none')
"
```

Expected: all events present, `Missing: none`.

---

## Task 13 (updated): Sync to plugins/claudetools/

- [ ] **Step 1: Run the sync**

```bash
rsync -a --delete \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='logs/' \
  /home/maverick/projects/marketplace-dev/plugin/ \
  /home/maverick/projects/marketplace-dev/plugins/claudetools/
```

- [ ] **Step 2: Verify codebase-pilot is gone from plugins/claudetools/**

```bash
ls plugins/claudetools/codebase-pilot 2>/dev/null && echo "PROBLEM: still present" || echo "clean"
ls plugins/claudetools/agent-mesh/ 2>/dev/null && echo "PROBLEM: mesh dir still present" || echo "clean"
grep "mesh-lifecycle" plugins/claudetools/hooks/hooks.json && echo "PROBLEM: mesh in hooks.json" || echo "clean"
grep "codebase-pilot" plugins/claudetools/hooks/hooks.json && echo "PROBLEM: codebase-pilot in hooks.json" || echo "clean"
```

Expected: all lines print `clean`.

---

## Task 14 (updated): Commit and push

- [ ] **Step 1: Review final diff**

```bash
git diff --stat HEAD
```

- [ ] **Step 2: Stage all changes**

```bash
git add plugin/ plugins/claudetools/
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: replace codebase-pilot with srcpilot, remove agent-mesh, restore hooks

codebase-pilot → srcpilot:
- Delete bundled codebase-pilot package (src, dist, node_modules)
- Move codebase-pilot/scripts/session-index.sh → scripts/session-index.sh
- Update hooks.json: 3 session-index.sh paths from codebase-pilot/ to scripts/
- Update session-start-dispatcher.sh: path + ensure-srcpilot.sh step
- Add scripts/ensure-srcpilot.sh: one-time auto-install of srcpilot if missing
- Update codebase-explorer SKILL.md: all CLI invocations → srcpilot, add 7 new modes
  (why, next, ambiguities, budget, exports, cycles, implementations)
- Update codebase-navigation rule: extend command table with new srcpilot commands
- Update task-manager SKILL.md, enrichment-agent.md, workflow-patterns.md: → srcpilot
- Update prompt-improver generation-agent-prompt.md: → srcpilot

agent-mesh retired:
- Delete agent-mesh/cli.js, mesh-lifecycle.sh, validators/mesh-lock.sh
- Remove all 4 mesh-lifecycle hook entries from hooks.json
- Remove mesh references from session-index.sh, inject-prompt-context.sh,
  track-file-edits.sh, session-start-dispatcher.sh, pre-edit-gate.sh

hooks restored (wrongly gutted by prior agent):
- Restore pre-tool-dispatcher.sh with all 6 validators
- Restore post-tool-dispatcher.sh with all post-tool hooks
- Restore pre-bash-gate.sh with ai-safety, unasked-restructure, deploy-loop
- Restore hooks.json with TaskCompleted, SubagentStop, TeammateIdle, Stop,
  PostToolUseFailure, Notification, ConfigChange, WorktreeCreate

fixes:
- failure-pattern-detector.sh: add rg-missing and worktree-path benign patterns
- session-stop-gate.sh: downgrade uncommitted-changes hard-block to warning
EOF
)"
```

- [ ] **Step 4: Push**

```bash
git push origin main
```

---

## Self-Review

**Spec coverage:**
- ✓ Mesh removed: all files deleted, all hooks.json entries removed, all script references cleaned
- ✓ codebase-pilot replaced: bundled package deleted, session-index.sh moved, all CLI references updated to srcpilot
- ✓ New srcpilot commands exposed: 7 new modes in codebase-explorer SKILL.md and navigation rule
- ✓ srcpilot auto-install: ensure-srcpilot.sh + marker file pattern
- ✓ Gutted dispatchers restored: pre-tool, post-tool, pre-bash-gate
- ✓ Good working-tree changes preserved: failure-pattern-detector, session-stop-gate, inject-prompt-context, track-file-edits
- ✓ decision=allow exit=2 investigated and likely fixed by mesh inbox removal
- ✓ plugins/claudetools/ synced
- ✓ track-worktree-session.sh preserved (not mesh-dependent, records crash-recovery metadata)
