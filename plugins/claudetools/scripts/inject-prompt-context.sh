#!/bin/bash
# inject-prompt-context.sh — UserPromptSubmit hook
# Injects lightweight context (git state, active tasks, recent failures)
# into every prompt. Stdout becomes visible context to Claude.
# Must always exit 0 and complete under 5 seconds.

source "$(dirname "$0")/hook-log.sh"
source "$(dirname "$0")/lib/detect-project.sh"

INPUT=$(cat)

hook_log "inject-prompt-context started"

# --- Git section ---
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  uncommitted=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
  commits=$(git log --oneline -3 --no-decorate 2>/dev/null)

  if [ -n "$branch" ]; then
    echo "[git] branch: ${branch} | uncommitted: ${uncommitted}"
    if [ -n "$commits" ]; then
      echo "[git] recent commits:"
      echo "$commits" | while IFS= read -r line; do
        echo "  $line"
      done
    fi
  fi
fi

# --- Active task section ---
task_dir="$HOME/.claude/tasks"
if [ -d "$task_dir" ]; then
  for f in "$task_dir"/*.json; do
    [ -f "$f" ] || continue
    status=$(jq -r '.status // ""' "$f" 2>/dev/null)
    if [ "$status" = "in_progress" ]; then
      title=$(jq -r '.title // "untitled"' "$f" 2>/dev/null)
      echo "[task] active: ${title}"
    fi
  done
fi

# --- Recent failures section ---
failure_log="/tmp/claude-failures-${PPID}.jsonl"
if [ -f "$failure_log" ]; then
  cutoff=$(date -v-5M +%s 2>/dev/null || date -d '5 minutes ago' +%s 2>/dev/null)
  if [ -n "$cutoff" ]; then
    count=0
    while IFS= read -r line; do
      ts=$(echo "$line" | jq -r '.timestamp // 0' 2>/dev/null)
      if [ -n "$ts" ] && [ "$ts" -ge "$cutoff" ] 2>/dev/null; then
        count=$((count + 1))
      fi
    done < "$failure_log"
    if [ "$count" -gt 0 ]; then
      echo "[warn] Recent failures: ${count} (check approach)"
    fi
  fi
fi

# --- Active memory retrieval (FTS5) ---
if command -v sqlite3 &>/dev/null; then
  source "$(dirname "$0")/lib/ensure-db.sh"
  source "$(dirname "$0")/lib/adaptive-weights.sh"
  if ensure_metrics_db 2>/dev/null; then
    # Check if memories table has any rows
    MEM_COUNT=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM memories;" 2>/dev/null || echo "0")
    if [ "$MEM_COUNT" -gt 0 ] 2>/dev/null; then
      # Extract user's prompt text from hook input
      PROMPT_TEXT=$(echo "$INPUT" | jq -r '.content // .message // ""' 2>/dev/null || true)
      if [ -z "$PROMPT_TEXT" ]; then
        PROMPT_TEXT=$(echo "$INPUT" | jq -r '
          if (.content | type) == "array" then
            [.content[] | select(type == "string" or .type == "text") |
             if type == "string" then . else .text end] | join(" ")
          else (.content // "") end
        ' 2>/dev/null || true)
      fi

      if [ -n "$PROMPT_TEXT" ] && [ ${#PROMPT_TEXT} -gt 5 ]; then
        # Extract key terms: words 4+, CamelCase, snake_case, hyphenated identifiers
        TERMS=$(echo "$PROMPT_TEXT" | \
          grep -oE '\b[A-Z][a-zA-Z0-9]{2,}\b|\b[a-z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*\b|\b[a-z_]{4,}\b|\b[a-z]+-[a-z]+(-[a-z]+)*\b' | \
          tr '[:upper:]' '[:lower:]' | sed 's/-/ /g' | tr ' ' '\n' | \
          grep -vE '^(this|that|with|from|have|been|will|would|could|should|there|their|about|which|when|what|make|just|more|also|than|them|then|these|those|each|into|some|like|over|such|only|after|before|other|your|does|were|being|here|very|most|much|need|want|help|please|using|file|code|sure|okay|take|look|know|find|they|been|done|change|changes|implement|check|test|system|work)$' | \
          sort -u | head -10)

        if [ -n "$TERMS" ]; then
          # Build FTS5 MATCH query: term1 OR term2 OR term3
          FTS_QUERY=$(echo "$TERMS" | tr '\n' ' ' | sed 's/ *$//' | sed 's/ / OR /g')

          MODEL_FAMILY=$(detect_model_family 2>/dev/null || echo "unknown")
          MEM_LIMIT=$(get_threshold "memory_retrieval_limit" "$MODEL_FAMILY")
          MEM_LIMIT=${MEM_LIMIT%.*}

          # Composite ranking: FTS relevance + confidence + access + type + recency - verbosity penalty
          # Type weights: feedback=3 (actionable), reference=2, user=2, project=1
          # Verbosity penalty: long content matches broadly — penalize to favor specific memories
          MATCHED=$(sqlite3 -separator $'\x1f' "$METRICS_DB" \
            "SELECT m.id, m.type, m.description, m.content FROM memories m
             INNER JOIN (
               SELECT rowid, rank FROM memories_fts WHERE memories_fts MATCH '${FTS_QUERY}'
             ) fts ON m.rowid = fts.rowid
             WHERE m.confidence > 0.3
             ORDER BY (
               fts.rank * -1.0
               + m.confidence * 5.0
               + MIN(m.access_count, 10) * 0.5
               + CASE m.type
                   WHEN 'feedback' THEN 3.0
                   WHEN 'reference' THEN 2.0
                   WHEN 'user' THEN 2.0
                   WHEN 'project' THEN 1.0
                   ELSE 0.0
                 END
               + CASE WHEN m.last_accessed IS NOT NULL
                   THEN MAX(0, 7.0 - julianday('now') + julianday(m.last_accessed)) * 0.3
                   ELSE 0.0
                 END
               - CASE WHEN LENGTH(m.content) > 500 THEN 2.0
                      WHEN LENGTH(m.content) > 200 THEN 1.0
                      ELSE 0.0
                 END
             ) DESC
             LIMIT ${MEM_LIMIT};" 2>/dev/null || true)

          if [ -n "$MATCHED" ]; then
            MATCH_COUNT=$(echo "$MATCHED" | grep -c $'\x1f' || echo 1)
            hook_log "inject-prompt-context: injecting ${MATCH_COUNT} memories for: ${FTS_QUERY}"
            # Output memory content (truncated) for richer context
            echo "$MATCHED" | while IFS=$'\x1f' read -r mid mtype mdesc mcontent; do
              [ -z "$mdesc" ] && continue
              # For short memories, inject full content; for long ones, description + first line of content
              if [ ${#mcontent} -le 200 ] || [ -z "$mcontent" ]; then
                echo "[memory:${mtype}] ${mdesc}"
              else
                # Extract first actionable line from content (skip frontmatter)
                FIRST_LINE=$(echo "$mcontent" | grep -v '^---' | grep -v '^$' | grep -v '^name:' | grep -v '^description:' | grep -v '^type:' | head -1)
                if [ -n "$FIRST_LINE" ] && [ "$FIRST_LINE" != "$mdesc" ]; then
                  echo "[memory:${mtype}] ${mdesc} — ${FIRST_LINE}"
                else
                  echo "[memory:${mtype}] ${mdesc}"
                fi
              fi
            done
            # Update access stats using the same FTS query (avoids multi-line content parsing issues)
            sqlite3 "$METRICS_DB" \
              "UPDATE memories SET access_count = access_count + 1, last_accessed = datetime('now')
               WHERE rowid IN (
                 SELECT rowid FROM memories_fts WHERE memories_fts MATCH '${FTS_QUERY}'
                 ORDER BY rank LIMIT ${MEM_LIMIT}
               ) AND confidence > 0.3;" 2>/dev/null || true
          fi
        fi
      fi
    fi
  fi
fi

# Anti-hallucination reinforcement — injected on every prompt, survives context compaction
# Per prompting playbook: ALWAYS/NEVER emphasis, specific failure names, not abstract principles
echo "[accuracy] ALWAYS read files before claiming their contents. NEVER report test/build results without running the command. NEVER assume — use Read, Grep, Bash to verify. Cite file:line for every code claim."

hook_log "inject-prompt-context complete"
exit 0
