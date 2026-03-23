#!/usr/bin/env bash
# Validator: session stop gate — multi-tier quality gate
# Sourced by the dispatcher after hook_init() has been called.
# Globals used: INPUT, MODEL_FAMILY
# Calls: get_threshold, record_hook_outcome, hook_log
# Returns: 0 = all clear, 1 = tier 2/3 warnings, 2 = tier 1 hard block

validate_stop_gate() {
  # Prevent infinite loops — if this is a re-evaluation after blocking, allow stop
  local STOP_HOOK_ACTIVE
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // empty' 2>/dev/null || true)
  if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    hook_log "stop_hook_active=true, allowing stop"
    return 0
  fi

  local CWD
  CWD=$(echo "$INPUT" | jq -r '.cwd // "."' 2>/dev/null || echo ".")

  # Track results for summary
  local TIER1_PASS=()
  local TIER1_FAIL=()
  local TIER2_WARNINGS=()
  local TIER3_RESULT=""
  local HOOK_DECISION="" HOOK_REASON="" LARGE_CHANGE=""

  _stop_summary() {
    # Only print failures and warnings — skip passes and decoration
    local f w
    for f in "${TIER1_FAIL[@]}"; do
      echo "$f" >&2
    done
    for w in "${TIER2_WARNINGS[@]}"; do
      echo "$w" >&2
    done
    if [ -n "$TIER3_RESULT" ] && ! echo "$TIER3_RESULT" | grep -q "PASS\|SKIPPED"; then
      echo "$TIER3_RESULT" >&2
    fi
  }

  # ═══════════════════════════════════════════════════════════════
  # TIER 1: Deterministic checks (return 2 on failure)
  # ═══════════════════════════════════════════════════════════════

  local IS_GIT=0
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IS_GIT=1
  fi

  # --- 1a. Main branch check ---
  if [ "$IS_GIT" -eq 1 ]; then
    local CURRENT_BRANCH
    CURRENT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
      local HAS_CHANGES
      HAS_CHANGES=$(git -C "$CWD" status --porcelain 2>/dev/null | grep -vE '^[?][?] [.](claude|DS_Store)|[.]lock$|[.]tsbuildinfo$|^node_modules/|/logs/|^[?][?] [.]tasks/' | head -1 || true)
      if [ -n "$HAS_CHANGES" ]; then
        TIER1_FAIL+=("On $CURRENT_BRANCH with uncommitted changes — create a feature branch first.")
        HOOK_DECISION="reject"; HOOK_REASON="on main branch with changes"
        _stop_summary
        record_hook_outcome "session-stop-gate" "Stop" "block" "" "" ""
        return 2
      else
        TIER2_WARNINGS+=("On $CURRENT_BRANCH — consider using a feature branch for code changes.")
      fi
    else
      TIER1_PASS+=("Branch: $CURRENT_BRANCH (not main/master)")
    fi
  fi

  # --- 1b. Uncommitted changes ---
  local CHANGED_FILES=""
  if [ "$IS_GIT" -eq 1 ]; then
    local STAGED UNSTAGED UNTRACKED ALL_CHANGED
    STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || true)
    UNSTAGED=$(git -C "$CWD" diff --name-only 2>/dev/null || true)
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true)
    ALL_CHANGED=$(printf '%s\n%s\n%s' "$STAGED" "$UNSTAGED" "$UNTRACKED" | sort -u | sed '/^$/d')
    # Filter out system/artifact files that aren't real code changes
    CHANGED_FILES=$(echo "$ALL_CHANGED" | grep -vE '^\.(claude|DS_Store)|\.lock$|\.tsbuildinfo$|^node_modules/|^\.git/|/logs/|^\.tasks/' | sed '/^$/d' || true)

    if [ -n "$CHANGED_FILES" ]; then
      local FILE_COUNT
      FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')

      # Check if team agents are actively running — if so, downgrade to warning
      local AGENTS_ACTIVE=0
      local MESH_CLI
      MESH_CLI="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/agent-mesh/cli.js"
      if [ -f "$MESH_CLI" ]; then
        local AGENT_OUTPUT
        AGENT_OUTPUT=$(node "$MESH_CLI" list --brief 2>/dev/null || true)
        if [ -n "$AGENT_OUTPUT" ] && ! echo "$AGENT_OUTPUT" | grep -q "No active agents"; then
          AGENTS_ACTIVE=1
        fi
      fi

      if [ "$AGENTS_ACTIVE" -eq 1 ]; then
        TIER2_WARNINGS+=("$FILE_COUNT uncommitted file(s) (agents still active — commit when they finish)")
        HOOK_DECISION="warn"; HOOK_REASON="uncommitted changes (agents active)"
      else
        TIER1_FAIL+=("$FILE_COUNT uncommitted file(s). Uncommitted work is lost when the session ends — commit or stash before stopping.")
        HOOK_DECISION="reject"; HOOK_REASON="uncommitted changes"
        _stop_summary
        record_hook_outcome "session-stop-gate" "Stop" "block" "" "" ""
        return 2
      fi
    else
      TIER1_PASS+=("No uncommitted changes")
    fi
  fi

  # If no git repo or no changes, skip remaining file-level checks
  if [ -z "$CHANGED_FILES" ] && [ "$IS_GIT" -eq 0 ]; then
    TIER1_PASS+=("Not a git repo — skipping file checks")
    _stop_summary
    record_hook_outcome "session-stop-gate" "Stop" "allow" "" "" ""
    return 0
  fi

  # --- 1c. Sensitive files staged ---
  if [ "$IS_GIT" -eq 1 ]; then
    local SENSITIVE_STAGED
    SENSITIVE_STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null | grep -iE '\.(env|key|pem|p12|pfx|keystore)$|credentials|secrets' || true)
    if [ -n "$SENSITIVE_STAGED" ]; then
      TIER1_FAIL+=("Sensitive files staged: $(echo "$SENSITIVE_STAGED" | tr '\n' ', ') — unstage these before committing to avoid leaking credentials.")
      HOOK_DECISION="reject"; HOOK_REASON="sensitive files staged"
      _stop_summary
      record_hook_outcome "session-stop-gate" "Stop" "block" "" "" ""
      return 2
    else
      TIER1_PASS+=("No sensitive files staged")
    fi
  fi

  # --- 1d. Stub/TODO/FIXME patterns in recently changed files ---
  # Check committed files from recent work (last commit vs HEAD~1)
  local RECENT_CODE_FILES=""
  if [ "$IS_GIT" -eq 1 ]; then
    RECENT_CODE_FILES=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|py|go|rs|rb|java)$' | grep -vE '\.test\.|\.spec\.|__tests__|__mocks__' || true)
  fi

  local STUB_VIOLATIONS=""
  local STUB_COUNT=0
  if [ -n "$RECENT_CODE_FILES" ]; then
    local file FULL_PATH COUNT
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      FULL_PATH="$file"
      [ "${file:0:1}" != "/" ] && FULL_PATH="$CWD/$file"
      [ -f "$FULL_PATH" ] || continue

      COUNT=$(grep -cE 'throw new Error\(.*(not implemented|todo|fixme|placeholder)|//\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError|HACK:' "$FULL_PATH" 2>/dev/null || true)
      COUNT=${COUNT:-0}
      if [ "$COUNT" -gt 0 ]; then
        STUB_VIOLATIONS="${STUB_VIOLATIONS}\n  $(basename "$file"): ${COUNT} stub/TODO markers"
        STUB_COUNT=$((STUB_COUNT + COUNT))
      fi
    done <<< "$RECENT_CODE_FILES"
  fi

  if [ "$STUB_COUNT" -gt 0 ]; then
    TIER1_FAIL+=("$STUB_COUNT stub/TODO patterns in recent changes — implement or remove them before stopping.")
    HOOK_DECISION="reject"; HOOK_REASON="stubs in changed files"
    _stop_summary
    printf '%b\n' "$STUB_VIOLATIONS" >&2
    record_hook_outcome "session-stop-gate" "Stop" "block" "" "" ""
    return 2
  else
    TIER1_PASS+=("No stub/TODO patterns in recent changes")
  fi

  # ═══════════════════════════════════════════════════════════════
  # TIER 2: Semantic checks (grep-based, return 1 = warning)
  # ═══════════════════════════════════════════════════════════════

  # --- 2a. Weasel phrases in recent agent transcript ---
  # The INPUT may contain transcript or tool output from the session
  local WEASEL_HITS
  WEASEL_HITS=$(echo "$INPUT" | grep -oiE 'should work|looks correct|appears to|I believe this fixes|it should be fine|probably works|seems to work|I think this is right|this might fix|likely resolves' 2>/dev/null || true)
  if [ -n "$WEASEL_HITS" ]; then
    local WEASEL_COUNT
    WEASEL_COUNT=$(echo "$WEASEL_HITS" | wc -l | tr -d ' ')
    # Threshold: 3+ weasel phrases = pattern of unverified confidence
    # A single "should work" is normal language, not a red flag
    if [ "$WEASEL_COUNT" -ge 3 ]; then
      TIER2_WARNINGS+=("$WEASEL_COUNT uncertain phrases detected — verify claims with tests, not confidence")
    fi
  fi

  # --- 2b. Scope check on recent commit ---
  if [ "$IS_GIT" -eq 1 ]; then
    local RECENT_CHANGED
    RECENT_CHANGED=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l | tr -d ' ' || true)
    RECENT_CHANGED=${RECENT_CHANGED:-0}
    [[ "$RECENT_CHANGED" =~ ^[0-9]+$ ]] || RECENT_CHANGED=0
    LARGE_CHANGE=$(get_threshold "large_change_threshold")
    LARGE_CHANGE=${LARGE_CHANGE%.*}
    if [ "$RECENT_CHANGED" -gt "$LARGE_CHANGE" ]; then
      TIER2_WARNINGS+=("Large change set: $RECENT_CHANGED files in last commit — verify scope matches the task")
    fi
  fi

  # --- 2c. Multi-signal convergence check ---
  if [ -f "$METRICS_DB" ] 2>/dev/null && command -v sqlite3 &>/dev/null; then
    local SESSION_ID
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
    if [ -n "$SESSION_ID" ]; then
      local CONVERGENCE
      CONVERGENCE=$(sqlite3 "$METRICS_DB" \
        "SELECT tool_name, COUNT(DISTINCT hook_name) as signals
         FROM hook_outcomes
         WHERE session_id = '$SESSION_ID'
           AND decision IN ('block', 'warn')
           AND tool_name IS NOT NULL AND tool_name != ''
         GROUP BY tool_name
         HAVING signals >= 3
         ORDER BY signals DESC
         LIMIT 3;" 2>/dev/null || true)
      if [ -n "$CONVERGENCE" ]; then
        local HOTSPOTS=""
        while IFS='|' read -r fname scount; do
          [ -z "$fname" ] && continue
          HOTSPOTS="${HOTSPOTS}  $(basename "$fname"): $scount independent signals\n"
        done <<< "$CONVERGENCE"
        if [ -n "$HOTSPOTS" ]; then
          TIER2_WARNINGS+=("Convergence hotspot(s) — multiple guardrails flagged the same file(s):")
          while IFS= read -r line; do
            [ -n "$line" ] && TIER2_WARNINGS+=("$line")
          done <<< "$(printf '%b' "$HOTSPOTS")"
        fi
      fi
    fi
  fi

  # ═══════════════════════════════════════════════════════════════
  # TIER 3: AI inference (optional, graceful degradation)
  # ═══════════════════════════════════════════════════════════════

  # Only run AI tier if there are recent code changes to review
  if [ "$IS_GIT" -eq 1 ]; then
    local DIFF DIFF_LINES
    DIFF=$(git -C "$CWD" diff HEAD~1 HEAD 2>/dev/null || true)
    DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

    local AI_AUDIT_LIMIT
    AI_AUDIT_LIMIT=$(get_threshold "ai_audit_diff_threshold")
    AI_AUDIT_LIMIT=${AI_AUDIT_LIMIT%.*}
    if [ "$DIFF_LINES" -gt "$AI_AUDIT_LIMIT" ]; then
      local RECENT_FILE_LIST
      RECENT_FILE_LIST=$(git -C "$CWD" diff --name-only HEAD~1 HEAD 2>/dev/null | head -20 || true)

      local AI_PROMPT="You are a session-end quality auditor. An agent is about to stop working. Review the diff from the last commit for completeness and quality issues.

<audit_categories>
1. INCOMPLETE: Functions declared but have stub/placeholder bodies. Endpoints with no real logic.
   WRONG: \"Some functions might be incomplete\"
   CORRECT: \"- [INCOMPLETE] src/api.ts:42: fetchUsers() has empty body\"

2. CLAIMED-NOT-DONE: Comments saying 'implemented X' but the code doesn't actually do X.
   WRONG: \"Code looks like it might not match comments\"
   CORRECT: \"- [CLAIMED-NOT-DONE] lib/auth.ts:15: comment says 'validates JWT' but function returns true unconditionally\"

3. MISSING_ERROR_HANDLING: New API endpoints or async operations with no error handling at all.
   WRONG: \"Error handling could be improved\"
   CORRECT: \"- [MISSING_ERROR_HANDLING] routes/users.ts:28: async db.query() with no try/catch\"

4. HARDCODED: Values that should clearly be configurable or come from config/env but are inline constants.
   WRONG: \"Some values might be hardcoded\"
   CORRECT: \"- [HARDCODED] config.ts:5: API URL 'http://localhost:3000' should come from env\"
</audit_categories>

NEVER speculate about what 'might' be an issue. ALWAYS cite a specific file:line.

<changed_files>
${RECENT_FILE_LIST}
</changed_files>

<output_rules>
Format each finding as: - [CATEGORY] file:line: description
If no issues found, respond with exactly: CLEAN
Keep response under 8 lines. No preamble. No praise.
</output_rules>"

      hook_log "Tier 3: invoking AI audit on ${DIFF_LINES}-line diff"

      local AI_RESULT
      AI_RESULT=$(echo "$DIFF" | timeout 30 claude -p "$AI_PROMPT" --no-input --model haiku 2>/dev/null || echo "AI_UNAVAILABLE")

      if [ "$AI_RESULT" = "AI_UNAVAILABLE" ]; then
        TIER3_RESULT="[SKIPPED] AI audit unavailable (timeout or CLI not found)"
        hook_log "Tier 3: AI unavailable — skipped"
      elif echo "$AI_RESULT" | grep -qi "^CLEAN$"; then
        TIER3_RESULT="[PASS] AI audit found no issues"
        hook_log "Tier 3: CLEAN"
      else
        TIER3_RESULT="[FINDINGS] AI audit flagged issues"
        TIER2_WARNINGS+=("AI audit findings (non-blocking):")
        local line
        while IFS= read -r line; do
          [ -n "$line" ] && TIER2_WARNINGS+=("  $line")
        done <<< "$AI_RESULT"
        hook_log "Tier 3: findings reported"
      fi
    else
      TIER3_RESULT="[SKIPPED] Diff too small ($DIFF_LINES lines) — not worth AI audit"
    fi
  else
    TIER3_RESULT="[SKIPPED] Not a git repo"
  fi

  # ═══════════════════════════════════════════════════════════════
  # FINAL DECISION
  # ═══════════════════════════════════════════════════════════════

  # Tier 1 all passed (otherwise we'd have returned already)
  # Check if Tier 2/3 produced warnings
  if [ ${#TIER2_WARNINGS[@]} -gt 0 ]; then
    HOOK_DECISION="warn"; HOOK_REASON="tier 2/3 warnings"
    _stop_summary
    record_hook_outcome "session-stop-gate" "Stop" "warn" "" "large_change_threshold" "${LARGE_CHANGE:-}" "$MODEL_FAMILY"
    return 1
  fi

  # All clear
  HOOK_DECISION="allow"; HOOK_REASON="all tiers passed"
  _stop_summary
  record_hook_outcome "session-stop-gate" "Stop" "allow" "" "" ""
  return 0
}
