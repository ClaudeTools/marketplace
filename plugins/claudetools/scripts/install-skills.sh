#!/bin/bash
# install-skills.sh — Install plugin skills as user-level skills (unprefixed)
#
# Creates symlinks from ~/.claude/skills/<name> → ${CLAUDE_PLUGIN_ROOT}/skills/<name>/
# so skills register as "design" instead of "claudetools:design".
#
# Runs on SessionStart. Idempotent — safe to run every session.
# Skips existing non-symlink directories (user's own skills take precedence).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/skills"

[ -d "$SKILLS_SRC" ] || exit 0

# Determine target: global (~/.claude/skills/) for marketplace installs,
# project (.claude/skills/) for local/dev plugins
if [[ "${CLAUDE_PLUGIN_ROOT:-}" == "$HOME/.claude/plugins/"* ]]; then
  TARGET="$HOME/.claude/skills"
else
  # Local/dev install — use project .claude/skills/
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  TARGET="$PROJECT_ROOT/.claude/skills"
fi

mkdir -p "$TARGET"

for skill_dir in "$SKILLS_SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  [ -f "$skill_dir/SKILL.md" ] || continue

  name="$(basename "$skill_dir")"
  dest="$TARGET/$name"

  # Skip if user has their own non-symlink skill (don't overwrite)
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    continue
  fi

  # For project-level installs, skip if the skill already exists globally
  # to avoid duplicate registration (Claude Code scans both directories)
  if [ "$TARGET" != "$HOME/.claude/skills" ] && [ -e "$HOME/.claude/skills/$name" ]; then
    continue
  fi

  # Create or update symlink
  ln -sfn "$skill_dir" "$dest"
done
