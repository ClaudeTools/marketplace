#!/usr/bin/env bash
# memory-validate.sh — Detect contradictions between CLAUDE.md and memory file directives.
# Informational only. Always exits 0.

# Detect repo root: git toplevel or CLAUDE_PLUGIN_ROOT parent
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$REPO_ROOT" ]] && REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Claude Code stores memory at ~/.claude/projects/<mangled-path>/memory/
MEMORY_DIR="$HOME/.claude/projects/$(echo "$REPO_ROOT" | sed 's|^/|-|' | tr '/' '-')/memory"
# Worktree fallback: if memory dir doesn't exist, try the main repo's memory
if [[ ! -d "$MEMORY_DIR" ]]; then
  MAIN_ROOT="$(git -C "$REPO_ROOT" worktree list 2>/dev/null | head -1 | awk '{print $1}')"
  if [[ -n "$MAIN_ROOT" ]] && [[ "$MAIN_ROOT" != "$REPO_ROOT" ]]; then
    MEMORY_DIR="$HOME/.claude/projects/$(echo "$MAIN_ROOT" | sed 's|^/|-|' | tr '/' '-')/memory"
  fi
fi
DPAT='(always|never|must|don'"'"'t|do not|NEVER|ALWAYS|CRITICAL|IMPORTANT)'

# Collect directives from a file, skipping frontmatter/comments. Format: "source_label|line"
collect_directives() {
  local file="$1" label="$2" in_fm=0 past_fm=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [ "$in_fm" -eq 0 ] && [ "$past_fm" -eq 0 ] && [ "$line" = "---" ]; then in_fm=1; continue; fi
    if [ "$in_fm" -eq 1 ] && [ "$line" = "---" ]; then in_fm=0; past_fm=1; continue; fi
    [ "$in_fm" -eq 1 ] && continue
    echo "$line" | grep -qiE "$DPAT" && echo "$label|$line"
  done < "$file"
}

# Collect CLAUDE.md directives
mapfile -t CLAUDE_DIRECTIVES < <(
  for f in "$REPO_ROOT/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$REPO_ROOT/.claude/CLAUDE.md"; do
    [ -f "$f" ] && collect_directives "$f" "$(basename "$f")"
  done
)

[ "${#CLAUDE_DIRECTIVES[@]}" -eq 0 ] && exit 0

# Collect memory file directives
mapfile -t MEM_DIRECTIVES < <(
  if [ -d "$MEMORY_DIR" ]; then
    for mf in "$MEMORY_DIR"/*.md; do
      [[ "$(basename "$mf")" == "MEMORY.md" ]] && continue
      [ -f "$mf" ] && collect_directives "$mf" "$(basename "$mf")"
    done
  fi
)

[ "${#MEM_DIRECTIVES[@]}" -eq 0 ] && exit 0

# Extract first word after directive keyword
first_topic() {
  echo "$1" | grep -oiE '(always|never|must|don'"'"'t|do not)[[:space:]]+[a-z_-]+' | \
    head -1 | awk '{print tolower($NF)}'
}

get_verb() {
  echo "$1" | grep -oiE '^(always|never|must|don'"'"'t|do not)' | tr '[:upper:]' '[:lower:]'
}

is_negative() { echo "$1" | grep -qiE '^(never|don'"'"'t|do not)'; }
is_positive() { echo "$1" | grep -qiE '^(always|must)'; }

CONFLICTS=0
for cdirective in "${CLAUDE_DIRECTIVES[@]}"; do
  clabel="${cdirective%%|*}"; cline="${cdirective#*|}"
  ctopic=$(first_topic "$cline"); [ -z "$ctopic" ] && continue
  cverb=$(get_verb "$cline"); [ -z "$cverb" ] && continue

  for mdirective in "${MEM_DIRECTIVES[@]}"; do
    mlabel="${mdirective%%|*}"; mline="${mdirective#*|}"
    echo "$mline" | grep -qiE "$ctopic" || continue
    mverb=$(get_verb "$mline"); [ -z "$mverb" ] && continue

    CONFLICT=0
    is_positive "$cverb" && is_negative "$mverb" && CONFLICT=1
    is_negative "$cverb" && is_positive "$mverb" && CONFLICT=1

    if [ "$CONFLICT" -eq 1 ]; then
      echo "[memory-validate] Potential conflict detected:"
      echo "  $clabel: \"$cline\""
      echo "  Memory ($mlabel): \"$mline\""
      CONFLICTS=$((CONFLICTS + 1))
    fi
  done
done

[ "$CONFLICTS" -gt 0 ] && echo "[memory-validate] $CONFLICTS potential conflict(s) — review memory files for outdated directives."

exit 0
