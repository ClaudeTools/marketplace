# Worktree Safety Audit — Multi-Session Assumptions in claudetools Plugin

Audit date: 2026-03-23
Auditor: Claude Opus 4.6 (automated)
Scope: All `.sh` files under `plugin/scripts/`, `plugin/codebase-pilot/scripts/`, `plugin/skills/*/scripts/`, `plugin/task-system/`

---

## Summary Table

| Script | Categories | Severity |
|--------|-----------|----------|
| `plugin/scripts/inject-prompt-context.sh` | CAT-1, CAT-2, CAT-6 | HIGH |
| `plugin/scripts/edit-frequency-guard.sh` | CAT-1 | HIGH |
| `plugin/scripts/capture-outcome.sh` | CAT-1, CAT-4 | HIGH |
| `plugin/scripts/failure-pattern-detector.sh` | CAT-1 | HIGH |
| `plugin/scripts/track-file-reads.sh` | CAT-1 | MEDIUM |
| `plugin/scripts/track-file-edits.sh` | CAT-1 | MEDIUM |
| `plugin/scripts/validators/blind-edit.sh` | CAT-1, CAT-3 | HIGH |
| `plugin/codebase-pilot/scripts/session-index.sh` | CAT-3, CAT-5 | CRITICAL |
| `plugin/scripts/inject-session-context.sh` | CAT-3, CAT-8 | HIGH |
| `plugin/scripts/memory-consolidate.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/validators/memory-consolidate.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/memory-reflect.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/session-learn-negatives.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/validators/learn-negatives.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/validators/memory-check.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/dynamic-rules.sh` | CAT-3 | LOW |
| `plugin/scripts/archive-before-compact.sh` | CAT-2, CAT-3 | HIGH |
| `plugin/scripts/guard-context-reread.sh` | CAT-3 | MEDIUM |
| `plugin/scripts/reindex-on-edit.sh` | CAT-3 | LOW |
| `plugin/scripts/hook-log.sh` | CAT-4, CAT-7 | MEDIUM |
| `plugin/scripts/lib/telemetry.sh` | CAT-4, CAT-7 | MEDIUM |
| `plugin/scripts/lib/telemetry-sync.sh` | CAT-4 | LOW |
| `plugin/scripts/capture-failure.sh` | CAT-8 | MEDIUM |
| `plugin/scripts/lib/ensure-db.sh` | CAT-8 | MEDIUM |
| `plugin/scripts/memory-extract-fast.sh` | CAT-4 | LOW |
| `plugin/scripts/memory-extract-deep.sh` | CAT-4 | LOW |
| `plugin/scripts/validators/memory-deep.sh` | CAT-4 | LOW |
| `plugin/scripts/aggregate-session.sh` | CAT-6 | MEDIUM |
| `plugin/scripts/require-active-task.sh` | CAT-6 | MEDIUM |
| `plugin/scripts/validators/aggregate-session.sh` | CAT-6 | MEDIUM |
| `plugin/scripts/session-stop-gate.sh` | CAT-2 (partial) | LOW |
| `plugin/scripts/validators/stop-gate.sh` | (clean — uses CWD from input) | - |
| `plugin/scripts/enforce-git-commits.sh` | (clean — uses CWD from input) | - |
| `plugin/scripts/lib/detect-project.sh` | CAT-3 | LOW |
| `plugin/scripts/session-wrap-up.sh` | (clean — uses CWD from input) | - |
| `plugin/scripts/validators/session-wrap.sh` | (clean — uses CWD from input) | - |
| `plugin/skills/code-review/scripts/gather-diff.sh` | CAT-2 | MEDIUM |
| `plugin/skills/debug-investigator/scripts/gather-diagnostics.sh` | CAT-2 | MEDIUM |
| `plugin/skills/logs/scripts/lib/parse-jsonl.sh` | CAT-3 | LOW |

---

## Detailed Findings by Category

### CAT-1: PPID-KEYED TEMP FILES

PPID is the parent process ID. When multiple Claude Code sessions run in the same terminal (or when Claude spawns subagents that inherit the shell's PPID), PPID collides and temp files are shared/corrupted across sessions.

#### Finding 1.1 — `inject-prompt-context.sh` line 45

```bash
failure_log="/tmp/claude-failures-${PPID}.jsonl"
```

**Why it breaks:** Two sessions launched from the same shell share the same PPID. One session's failure count pollutes the other's, causing false "Recent failures" warnings.
**Severity:** HIGH
**Fix:** Use `session_id` from hook input: `SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')` and key the file as `/tmp/claude-failures-${SESSION_ID}.jsonl`.

#### Finding 1.2 — `edit-frequency-guard.sh` line 39

```bash
COUNTER_FILE="/tmp/claude-edit-counts-${PPID}"
```

**Why it breaks:** Two sessions editing different files share the same counter file. Session A's edits to `foo.ts` inflate Session B's count for `foo.ts`, causing premature churn warnings.
**Severity:** HIGH
**Fix:** Extract `session_id` from `$INPUT` and use `/tmp/claude-edit-counts-${SESSION_ID}`.

#### Finding 1.3 — `capture-outcome.sh` line 35

```bash
SPOOL_DIR="/tmp/claude-outcome-spool-${PPID}"
```

**Why it breaks:** Spool files from concurrent sessions interleave SQL INSERT statements in the same file, then flush a mixed batch to the DB. While data may still go to the right session_id column, the spool-file truncation after flush can lose the other session's pending inserts.
**Severity:** HIGH
**Fix:** Key on `session_id` from hook input.

#### Finding 1.4 — `failure-pattern-detector.sh` line 14

```bash
FAILURE_LOG="/tmp/claude-failures-${SESSION_ID:-$$}.jsonl"
```

**Why it breaks:** Falls back to `$$` (current script PID) when `SESSION_ID` is empty. `$$` is unique per script invocation so the fallback is harmless, but the primary key (`SESSION_ID`) is correctly derived from hook input. This is actually *mostly* safe, but the `$$` fallback means the log won't persist across hook invocations for that session — each hook run creates a new file.
**Severity:** MEDIUM (degraded tracking, not corruption)
**Fix:** Use `PPID` as a fallback instead of `$$` would be worse; the real fix is to ensure `SESSION_ID` is always populated.

#### Finding 1.5 — `track-file-reads.sh` line 23, `track-file-edits.sh` line 21

```bash
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$PPID"
fi
```

**Why it breaks:** When `session_id` is missing from hook input, the PPID fallback causes reads/edits tracking to collide across co-terminal sessions. The blind-edit guard then sees files read by a different session as "already read."
**Severity:** MEDIUM
**Fix:** Remove PPID fallback; if no session_id, skip tracking rather than using a shared key.

#### Finding 1.6 — `validators/blind-edit.sh` line 32

```bash
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$SESSION_ID" ] && SESSION_ID="$PPID"
```

**Why it breaks:** Same PPID collision as 1.5. Session A reads `config.ts`, Session B gets no blind-edit warning when editing `config.ts` without reading it, because they share the same reads file.
**Severity:** HIGH
**Fix:** Remove PPID fallback; return 0 (allow) when session_id is unavailable.

---

### CAT-2: BARE GIT COMMANDS

Git commands without `-C <dir>` use the shell's CWD. In worktrees, the CWD is the worktree directory, so bare `git` commands may report incorrect state (e.g., different branch, different staged files) if the hook's CWD doesn't match the session's project root.

#### Finding 2.1 — `inject-prompt-context.sh` lines 15-18

```bash
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || ...)
  uncommitted=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  commits=$(git log --oneline -3 --no-decorate 2>/dev/null)
```

**Why it breaks:** Uses bare `git` with no `-C` flag. If the hook process CWD differs from the session's working directory (e.g., hook was invoked from plugin root), the git state injected into the prompt will be wrong.
**Severity:** HIGH
**Fix:** Extract CWD from hook input (`echo "$INPUT" | jq -r '.cwd // "."'`) and use `git -C "$CWD"` for all commands.

#### Finding 2.2 — `archive-before-compact.sh` lines 26-31

```bash
git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
uncommitted_count=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
modified_files=$(git diff --name-only 2>/dev/null | ...)
recent_commits=$(git log --oneline -3 --format='%s' 2>/dev/null | ...)
```

**Why it breaks:** Same as 2.1 — bare git in a hook that archives state before compaction. Archives wrong branch/commit info if CWD != project root.
**Severity:** HIGH
**Fix:** Use CWD from hook input and `git -C "$CWD"`.

#### Finding 2.3 — `session-stop-gate.sh` line 34 (standalone version)

```bash
CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")
```

**Why it breaks:** This script *does* extract CWD from input, and uses `git -C "$CWD"` throughout. However, the fallback default is `"."` which could be wrong if the hook process CWD is not the project root.
**Severity:** LOW (fallback issue only)
**Fix:** The validator version (`validators/stop-gate.sh`) also uses `"."` fallback. Both should warn or skip when CWD is unavailable.

#### Finding 2.4 — `skills/code-review/scripts/gather-diff.sh` lines 9-28

```bash
git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null
git log --oneline -1
git diff HEAD~1..HEAD
```

**Why it breaks:** All bare `git` commands. This is a skill script invoked interactively, so the CWD is likely correct. But in worktrees, the skill could be invoked from the worktree directory while the user intends to review the main repo.
**Severity:** MEDIUM
**Fix:** Accept a `--cwd` argument or derive CWD from the calling context.

#### Finding 2.5 — `skills/debug-investigator/scripts/gather-diagnostics.sh` lines 8-10

```bash
echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git repo')"
git log --oneline -5 2>/dev/null || true
```

**Why it breaks:** Same as 2.4 — bare git in skill script.
**Severity:** MEDIUM

---

### CAT-3: PWD-BASED PATH DERIVATION

Using `$(pwd)` to derive memory directories, project roots, or index paths. In worktrees, `pwd` returns the worktree path (e.g., `/repo/.claude/worktrees/my-task`), which produces a different slug than the main repo path, fragmenting shared state.

#### Finding 3.1 — `session-index.sh` line 26

```bash
PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"
```

**Why it breaks:** In a worktree, `pwd` returns the worktree directory. The codebase index is then built at `<worktree>/.codeindex/` instead of `<repo>/.codeindex/`, fragmenting the index across worktrees.
**Severity:** CRITICAL — Each worktree builds its own index, wasting time and producing inconsistent symbol resolution.
**Fix:** Use `git -C "$(pwd)" rev-parse --show-toplevel` to find the actual repo root, falling back to `$(pwd)`.

#### Finding 3.2 — `inject-session-context.sh` line 45

```bash
MEMORY_DIR="$HOME/.claude/projects/$(pwd | sed 's|^/|-|' | tr '/' '-')/memory"
```

**Why it breaks:** Worktree path produces a different slug (e.g., `-home-user-repo-.claude-worktrees-task1` instead of `-home-user-repo`). Memory files stored under the worktree slug are invisible to the main session and vice versa.
**Severity:** HIGH
**Fix:** Derive the slug from the git toplevel, not from `$(pwd)`.

#### Finding 3.3 — `memory-consolidate.sh` line 27 and `validators/memory-consolidate.sh` line 22

```bash
CWD_SLUG=$(pwd | tr '/' '-')
```

**Why it breaks:** Same as 3.2. Memory consolidation runs against the wrong memory directory in worktrees.
**Severity:** MEDIUM

#### Finding 3.4 — `memory-reflect.sh` line 39

```bash
MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
```

**Why it breaks:** Uses `$CWD` from hook input (`.cwd`), which IS the worktree path when running in a worktree. Same slug fragmentation.
**Severity:** MEDIUM
**Fix:** Resolve `$CWD` to git toplevel before computing slug.

#### Finding 3.5 — `session-learn-negatives.sh` line 32, `validators/learn-negatives.sh` line 33

```bash
MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
```

**Why it breaks:** Same as 3.4.
**Severity:** MEDIUM

#### Finding 3.6 — `validators/memory-check.sh` line 36

```bash
local MEMORY_DIR="$HOME/.claude/projects/$(echo "$CWD" | sed 's|^/|-|' | tr '/' '-')/memory"
```

**Why it breaks:** Same as 3.4.
**Severity:** MEDIUM

#### Finding 3.7 — `validators/blind-edit.sh` line 48

```bash
local PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"
```

**Why it breaks:** In a worktree, `$(pwd)` returns the worktree directory. The session-ids file lookup at `$PROJECT_ROOT/.codeindex/session-ids` fails because the worktree has its own `.codeindex/` (or none at all).
**Severity:** HIGH

#### Finding 3.8 — `guard-context-reread.sh` line 29

```bash
PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"
```

**Why it breaks:** Same as 3.7. Session reads files looked up from wrong `.codeindex/` path.
**Severity:** MEDIUM

#### Finding 3.9 — `archive-before-compact.sh` line 54

```bash
SESSION_IDS_FILE="$(pwd)/.codeindex/session-ids"
```

**Why it breaks:** Same as 3.7. Pre-compact archive reads the wrong session-ids file.
**Severity:** HIGH

#### Finding 3.10 — `reindex-on-edit.sh` line 24

```bash
PROJECT_ROOT="${CODEBASE_PILOT_PROJECT_ROOT:-$(pwd)}"
```

**Why it breaks:** Incremental re-indexing targets wrong project root in worktrees.
**Severity:** LOW (indexes the worktree files, which may actually be correct for worktree-local edits)

#### Finding 3.11 — `lib/detect-project.sh` line 16

```bash
local dir="${1:-$(pwd)}"
```

**Why it breaks:** Falls back to `$(pwd)` to detect project type. In worktrees this is correct (worktree has the same project files), so this is low-severity.
**Severity:** LOW

#### Finding 3.12 — `dynamic-rules.sh` line 14

```bash
detect_project_type   # (which internally defaults to $(pwd))
```

**Why it breaks:** Same as 3.11 — correct in worktrees because project files are present.
**Severity:** LOW

#### Finding 3.13 — `lib/telemetry.sh` line 165

```bash
local memory_dir="$HOME/.claude/projects/$(pwd | sed 's|^/|-|' | tr '/' '-')/memory"
```

**Why it breaks:** `emit_session_start` counts memory files from wrong directory in worktrees. Telemetry metric only — does not affect behavior.
**Severity:** LOW

#### Finding 3.14 — `skills/logs/scripts/lib/parse-jsonl.sh` line 8-10

```bash
local cwd="${1:-$PWD}"
local slug
slug=$(echo "$cwd" | sed 's|^/|-|' | tr '/' '-')
```

**Why it breaks:** `resolve_project_dir()` derives the Claude Code project directory from `$PWD`. In worktrees, the wrong project dir is resolved, so log queries return no results.
**Severity:** LOW (interactive skill — user would notice and provide `--project`)

---

### CAT-4: SHARED FILE CONTENTION

Multiple sessions writing to the same log/candidates/spool file without flock or atomic operations, risking interleaved writes.

#### Finding 4.1 — `hook-log.sh` line 26

```bash
echo "${ts} | ${HOOK_NAME} | ..." >> "$HOOK_LOG_FILE"
```

**Why it breaks:** Multiple sessions append to the same `logs/hooks.log` simultaneously. Individual `echo` calls with `>>` are typically atomic on Linux for lines < PIPE_BUF (4096 bytes), but this is not guaranteed. Lines can interleave in pathological cases.
**Severity:** MEDIUM — log corruption is cosmetic, not data-losing.
**Fix:** Use `flock` for the append, or accept the minor risk.

#### Finding 4.2 — `lib/telemetry.sh` line 108

```bash
printf '...\n' >> "$_TELEMETRY_EVENTS_FILE" 2>/dev/null || true
```

**Why it breaks:** Same as 4.1. Multiple sessions appending JSONL to `events.jsonl`. Printf with `\n` is typically atomic for short lines.
**Severity:** MEDIUM

#### Finding 4.3 — `memory-extract-fast.sh` line 40

```bash
echo "{...}" >> "$CANDIDATES_FILE"
```

**Why it breaks:** Multiple sessions append to the same `memory-candidates.jsonl`. Low risk since sessions rarely end simultaneously.
**Severity:** LOW

#### Finding 4.4 — `memory-extract-deep.sh` line 106, `validators/memory-deep.sh` line 111

```bash
echo "{...}" >> "$CANDIDATES_FILE"
```

**Why it breaks:** Same as 4.3.
**Severity:** LOW

#### Finding 4.5 — `capture-outcome.sh` line 35 (also CAT-1)

```bash
SPOOL_DIR="/tmp/claude-outcome-spool-${PPID}"
```

**Why it breaks:** The PPID collision (CAT-1) makes this a CAT-4 issue too. Even with flock protecting the flush, the spool file is truncated after flush — losing any inserts appended by a concurrent session between the read and the truncation.
**Severity:** HIGH

---

### CAT-5: SESSION-IDS OVERWRITE

The codebase index `session-ids` file overwritten (not appended) on SessionStart, losing track of previous sessions.

#### Finding 5.1 — `session-index.sh` lines 69-70

```bash
if [ "$HOOK_EVENT" = "SessionStart" ] || [ "$HOOK_EVENT" = "WorktreeCreate" ]; then
  echo "$SESSION_ID" > "$INDEX_DIR/session-ids" 2>/dev/null || true
```

**Why it breaks:** Uses `>` (overwrite) instead of `>>` (append). When Session B starts while Session A is active, Session A's ID is erased. Session A's blind-edit guard can no longer look up cross-session reads because its ID is gone from `session-ids`. The `else` branch (line 73-75) correctly uses `>>` for SubagentStart.
**Severity:** CRITICAL — Active session loses cross-session read tracking, causing false blind-edit warnings.
**Fix:** Always append (`>>`) and implement a separate cleanup mechanism (e.g., remove stale session IDs when their reads files no longer exist in `/tmp/`).

---

### CAT-6: GLOBAL STATE READS

Reading from global directories (e.g., `~/.claude/tasks/`) without filtering by session, causing one session to see another's task state.

#### Finding 6.1 — `inject-prompt-context.sh` lines 32-42

```bash
task_dir="$HOME/.claude/tasks"
if [ -d "$task_dir" ]; then
  for f in "$task_dir"/*.json; do
    ...
    if [ "$status" = "in_progress" ]; then
      title=$(jq -r '.title // "untitled"' "$f" 2>/dev/null)
      echo "[task] active: ${title}"
    fi
  done
fi
```

**Why it breaks:** Injects ALL in_progress tasks from the global task directory into every session's prompt. Session A sees Session B's tasks as "active," potentially confusing the agent about what work is assigned to it.
**Severity:** HIGH
**Fix:** Filter tasks by session_id or by a task assignment mechanism.

#### Finding 6.2 — `aggregate-session.sh` lines 57-61 and `validators/aggregate-session.sh` lines 54-59

```bash
tasks_completed=$(find "$HOME/.claude/tasks" -name '*.json' -newer "$SESSION_MARKER" -exec grep -l '"status".*"completed"' {} + 2>/dev/null | wc -l)
```

**Why it breaks:** Counts ALL tasks completed after the session start marker, including tasks completed by other concurrent sessions. This inflates `tasks_completed` in session metrics.
**Severity:** MEDIUM — metrics inflation, not behavioral impact.
**Fix:** Filter by session_id in the task JSON if available.

#### Finding 6.3 — `require-active-task.sh` lines 34-47

```bash
TASK_DIR="$HOME/.claude/tasks"
...
while IFS= read -r task_file; do
  ...
  if [ "$STATUS" = "in_progress" ]; then
    FOUND_ACTIVE=true; break
  fi
done < <(find "$TASK_DIR" -name "*.json" -type f 2>/dev/null)
```

**Why it breaks:** Checks ALL tasks globally. Session A's in_progress task satisfies the gate for Session B, allowing Session B to edit code without its own task.
**Severity:** MEDIUM
**Fix:** Filter tasks by the current session's session_id.

---

### CAT-7: NON-ATOMIC LOG ROTATION

Log rotation checks (size check + mv) that race when multiple sessions rotate simultaneously.

#### Finding 7.1 — `hook-log.sh` lines 15-20

```bash
if [ -f "$HOOK_LOG_FILE" ]; then
  local size
  size=$(stat ... "$HOOK_LOG_FILE" ...)
  if [ "$size" -gt 5242880 ]; then
    mv -f "$HOOK_LOG_FILE" "${HOOK_LOG_FILE}.old"
  fi
fi
```

**Why it breaks:** TOCTOU race: two sessions check the size simultaneously, both see >5MB, both mv. The second mv overwrites the first's `.old` file. Meanwhile, a third session appending between the check and the mv writes to the now-vanished file (the inode still exists, but the directory entry points to the new empty file after mv).
**Severity:** MEDIUM — log data loss in the `.old` file, but hooks continue working.
**Fix:** Use `flock` around the rotation, or use `logrotate`-style atomic rotation with unique backup names.

#### Finding 7.2 — `lib/telemetry.sh` lines 63-70

```bash
if [ -f "$_TELEMETRY_EVENTS_FILE" ]; then
  local size
  size=$(stat ...)
  if [ "$size" -gt 10485760 ]; then
    mv -f "$_TELEMETRY_EVENTS_FILE" "${_TELEMETRY_EVENTS_FILE}.1" 2>/dev/null || true
  fi
fi
```

**Why it breaks:** Same TOCTOU race as 7.1. Two sessions rotating `events.jsonl` simultaneously can lose data.
**Severity:** MEDIUM

---

### CAT-8: SHARED DB WRITE CONTENTION

SQLite writes from concurrent sessions without WAL mode or busy timeouts, causing `SQLITE_BUSY` errors.

#### Finding 8.1 — `lib/ensure-db.sh` (entire file)

```bash
sqlite3 "$METRICS_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS ...
SQL
```

**Why it breaks:** The database is created with default journal mode (DELETE), not WAL. Under concurrent writes from multiple sessions, `SQLITE_BUSY` errors are frequent. Most writes have `2>/dev/null || true` which silently drops data.
**Severity:** MEDIUM — silent data loss in metrics, but never crashes.
**Fix:** Add `PRAGMA journal_mode=WAL;` and `PRAGMA busy_timeout=5000;` at DB creation time.

#### Finding 8.2 — `inject-session-context.sh` lines 88-96

```bash
sqlite3 "$METRICS_DB" "INSERT INTO memories ..." 2>/dev/null && INDEXED=$((INDEXED + 1))
```

**Why it breaks:** Bulk inserts during SessionStart from multiple sessions. Without WAL mode, concurrent inserts fail silently.
**Severity:** MEDIUM

#### Finding 8.3 — `capture-failure.sh` lines 28-31

```bash
sqlite3 "$METRICS_DB" \
  "INSERT INTO tool_outcomes ..." \
  "$session_id" "$tool_name" "$file_path" \
  2>/dev/null || true
```

**Why it breaks:** Direct insert without busy timeout. Concurrent failures across sessions may be silently dropped.
**Severity:** MEDIUM

#### Finding 8.4 — `lib/adaptive-weights.sh` line 94-96

```bash
(sqlite3 "$METRICS_DB" \
  "INSERT INTO hook_outcomes ..." 2>/dev/null || true) &
```

**Why it breaks:** Background insert without WAL or busy timeout. Backgrounding helps avoid blocking the hook, but the concurrent write can fail silently.
**Severity:** MEDIUM

---

## Unaffected Scripts

The following scripts were audited and found clean (no single-agent assumptions):

| Script | Notes |
|--------|-------|
| `plugin/scripts/lib/hook-input.sh` | No PWD/PPID usage; reads from stdin |
| `plugin/scripts/lib/hook-skip.sh` | Pure functions, no state |
| `plugin/scripts/lib/adaptive-weights.sh` | Uses session_id from INPUT/env; DB contention is CAT-8 |
| `plugin/scripts/session-stop-dispatcher.sh` | Dispatcher only; delegates to validators |
| `plugin/scripts/session-end-dispatcher.sh` | Dispatcher only |
| `plugin/scripts/pre-edit-gate.sh` | Dispatcher only |
| `plugin/scripts/pre-bash-gate.sh` | Dispatcher only |
| `plugin/scripts/post-bash-gate.sh` | Dispatcher only |
| `plugin/scripts/post-agent-gate.sh` | Dispatcher only |
| `plugin/scripts/task-completion-gate.sh` | Dispatcher only |
| `plugin/scripts/validate-content.sh` | Dispatcher only |
| `plugin/scripts/session-stop-gate.sh` | Uses CWD from input + `git -C`; clean |
| `plugin/scripts/validators/stop-gate.sh` | Uses CWD from input + `git -C`; clean |
| `plugin/scripts/enforce-git-commits.sh` | Uses CWD from input + `git -C`; clean |
| `plugin/scripts/session-wrap-up.sh` | Uses CWD from input; clean |
| `plugin/scripts/validators/session-wrap.sh` | Uses CWD from input; clean |
| `plugin/scripts/auto-approve-safe.sh` | Tool inspection only; no state |
| `plugin/scripts/desktop-alert.sh` | Notification only; no state |
| `plugin/scripts/config-audit-trail.sh` | Appends to log; minor CAT-4 risk but acceptable |
| `plugin/scripts/restore-after-compact.sh` | Uses session_id from input; keyed correctly |
| `plugin/scripts/memory-index.sh` | Uses FILE_PATH from input; no PWD/PPID |
| `plugin/scripts/enforce-read-efficiency.sh` | Stateless validation; no session state |
| `plugin/scripts/semantic-audit-agent.sh` | Uses CWD from input + `git -C`; clean |
| `plugin/scripts/block-stub-writes.sh` | Content validation; no state |
| `plugin/scripts/block-dangerous-bash.sh` | Content validation; no state |
| `plugin/scripts/detect-hardcoded-secrets.sh` | Content validation; no state |
| `plugin/scripts/detect-localhost-in-config.sh` | Content validation; no state |
| `plugin/scripts/check-mock-in-prod.sh` | Content validation; no state |
| `plugin/scripts/verify-no-stubs.sh` | Content validation; no state |
| `plugin/scripts/ai-safety-check.sh` | Content validation; no state |
| `plugin/scripts/block-unasked-restructure.sh` | Content validation; no state |
| `plugin/scripts/detect-unasked-deps.sh` | Content validation; no state |
| `plugin/scripts/enforce-deploy-then-verify.sh` | Content validation; no state |
| `plugin/scripts/detect-bulk-edit.sh` | Content validation; no state |
| `plugin/scripts/enforce-task-scope.sh` | Content validation; no state |
| `plugin/scripts/research-backing-gate.sh` | Content validation; no state |
| `plugin/scripts/audit-agent-output.sh` | Content validation; no state |
| `plugin/scripts/verify-subagent-independently.sh` | Content validation; no state |
| `plugin/scripts/enforce-codebase-pilot.sh` | Content validation; no state |
| `plugin/scripts/guard-sensitive-files.sh` | Content validation; no state |
| `plugin/scripts/enforce-task-quality.sh` | Content validation; no state |
| `plugin/scripts/enforce-team-usage.sh` | Content validation; no state |
| `plugin/scripts/doc-stale-detector.sh` | Content analysis; no session state |
| `plugin/scripts/doc-manager.sh` | Content analysis; no session state |
| `plugin/scripts/doc-index-generator.sh` | Content analysis; no session state |
| `plugin/scripts/tune-weights.sh` | CLI tool; not a hook — runs manually |
| `plugin/scripts/verify-task-done.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/verify-ran-checks.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/task-quality.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/task-done.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/git-commits.sh` | Uses CWD from INPUT + `git -C` |
| `plugin/scripts/validators/ran-checks.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/active-task.sh` | Global task check (see CAT-6) but no PWD/PPID issue |
| `plugin/scripts/validators/task-scope.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/research-backing.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/bulk-edit.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/prefer-edit-over-write.sh` | Uses INPUT; no PWD/PPID |
| `plugin/scripts/validators/dangerous-bash.sh` | Uses INPUT; no state |
| `plugin/scripts/validators/ai-safety.sh` | Uses INPUT; no state |
| `plugin/scripts/validators/unasked-restructure.sh` | Uses INPUT; no state |
| `plugin/scripts/validators/deploy-then-verify.sh` | Uses INPUT; no state |
| `plugin/scripts/validators/unasked-deps.sh` | Uses INPUT; no state |
| `plugin/scripts/validators/agent-output.sh` | Uses INPUT; no state |
| `plugin/scripts/validators/semantic-agent.sh` | Uses CWD from INPUT |
| `plugin/scripts/validators/stubs.sh` | Content validation |
| `plugin/scripts/validators/secrets.sh` | Content validation |
| `plugin/scripts/validators/localhost.sh` | Content validation |
| `plugin/scripts/validators/mocks.sh` | Content validation |
| `plugin/scripts/validators/doc-index.sh` | Content analysis |
| `plugin/scripts/validators/no-deferred-actions.sh` | Content validation |
| `plugin/scripts/lib/telemetry-sync.sh` | Uses flock; properly guarded |
| `plugin/task-system/start.sh` | MCP server bootstrap; no session state |
| `plugin/skills/prompt-improver/scripts/gather-context.sh` | Input-driven |
| `plugin/skills/prompt-improver/scripts/validate-prompt.sh` | Input-driven |
| `plugin/skills/tune-thresholds/scripts/analyse-metrics.sh` | DB reads only |
| `plugin/skills/session-dashboard/scripts/generate-report.sh` | DB reads only |
| `plugin/skills/docs-manager/scripts/*.sh` | File operations; no session state |
| `plugin/skills/frontend-design/scripts/*.sh` | Input-driven |
| `plugin/skills/field-review/scripts/*.sh` | Input-driven |
| `plugin/skills/logs/scripts/logs.sh` | Interactive query tool; PWD in parse-jsonl.sh is LOW |

---

## Totals

- **Scripts audited:** 97
- **Scripts with findings:** 33
- **Scripts clean:** 64

### Findings by category

| Category | Count | Description |
|----------|-------|-------------|
| CAT-1 | 6 | PPID-keyed temp files |
| CAT-2 | 5 | Bare git commands |
| CAT-3 | 14 | PWD-based path derivation |
| CAT-4 | 5 | Shared file contention |
| CAT-5 | 1 | Session-ids overwrite |
| CAT-6 | 3 | Global state reads |
| CAT-7 | 2 | Non-atomic log rotation |
| CAT-8 | 4 | Shared DB write contention |
| **Total** | **40** | |

### Findings by severity

| Severity | Count |
|----------|-------|
| CRITICAL | 2 |
| HIGH | 12 |
| MEDIUM | 18 |
| LOW | 8 |
