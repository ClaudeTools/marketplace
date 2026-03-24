#!/usr/bin/env bash
# auto-version.sh — Semantic version bumping for marketplace plugins
#
# Follows Semantic Versioning 2.0.0 (https://semver.org) with Conventional
# Commits (https://www.conventionalcommits.org) to determine bump level.
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │  Bump Rules (highest wins — one commit can only trigger one bump)  │
# ├────────┬────────────────────────────────────────────────────────────┤
# │ MAJOR  │ Breaking / incompatible changes to the public interface.  │
# │        │ Resets MINOR and PATCH to 0.                              │
# │        │ Triggers:                                                 │
# │        │   • "BREAKING CHANGE" or "BREAKING-CHANGE" in body/footer │
# │        │   • Bang suffix on any type: feat!:, fix!:, refactor!:    │
# │        │   • Commit subject contains [breaking]                    │
# │        │ Examples:                                                 │
# │        │   • Removing or renaming a hook script                    │
# │        │   • Changing hook input/output contract                   │
# │        │   • Removing a skill or changing its invocation           │
# │        │   • Changing settings.json schema                         │
# ├────────┼────────────────────────────────────────────────────────────┤
# │ MINOR  │ New functionality added in a backwards-compatible way.    │
# │        │ Resets PATCH to 0.                                        │
# │        │ Triggers:                                                 │
# │        │   • feat: or feat(scope):                                 │
# │        │ Examples:                                                 │
# │        │   • Adding a new hook script                              │
# │        │   • Adding a new skill                                    │
# │        │   • Adding new configuration options (with defaults)      │
# │        │   • New training chains or scoring capabilities           │
# ├────────┼────────────────────────────────────────────────────────────┤
# │ PATCH  │ Backwards-compatible bug fixes, docs, chores, refactors.  │
# │        │ Triggers (anything not MAJOR or MINOR):                   │
# │        │   • fix:, perf:, refactor:, style:, docs:, test:, chore:  │
# │        │   • ci:, build:, revert:                                  │
# │        │   • Any commit without a conventional prefix              │
# │        │ Examples:                                                 │
# │        │   • Bug fixes in existing hooks                           │
# │        │   • Threshold adjustments                                 │
# │        │   • Documentation updates                                 │
# │        │   • Test improvements                                     │
# │        │   • Performance optimizations                             │
# └────────┴────────────────────────────────────────────────────────────┘
#
# Analyses commits since last auto-bump, determines bump level per plugin,
# updates plugin.json + marketplace.json. Idempotent: no changes = no bump.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
PLUGINS_DIR="$REPO_ROOT/plugins"

# Skip if last commit was already an auto-bump (prevent loops)
LAST_MSG=$(git -C "$REPO_ROOT" log -1 --pretty=format:"%s" 2>/dev/null || true)
if [[ "$LAST_MSG" == chore:\ auto-bump* ]]; then
  echo "Last commit is auto-bump — skipping to prevent loop"
  exit 0
fi

# Find the last auto-bump commit SHA (or use initial commit if none)
LAST_BUMP_SHA=$(git -C "$REPO_ROOT" log --all --grep="^chore: auto-bump" --pretty=format:"%H" -1 2>/dev/null || true)
if [ -z "$LAST_BUMP_SHA" ]; then
  LAST_BUMP_SHA=$(git -C "$REPO_ROOT" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)
fi

echo "=== Auto-Version (SemVer 2.0.0) ==="
echo "Last bump ref: ${LAST_BUMP_SHA:0:8}"
echo ""

# Determine the bump level from a set of commit messages.
# Reads from stdin. Outputs: "major", "minor", or "patch".
determine_bump() {
  local bump="patch"
  local has_feat=false

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # MAJOR: breaking change indicators
    # - "BREAKING CHANGE:" or "BREAKING-CHANGE:" in commit body/footer (per spec)
    # - Bang suffix on type: feat!:, fix!:, refactor!:, etc.
    # - Explicit [breaking] tag in subject
    if [[ "$line" == *"BREAKING CHANGE"* ]] || \
       [[ "$line" == *"BREAKING-CHANGE"* ]] || \
       [[ "$line" =~ ^[a-z]+(\(.+\))?!: ]] || \
       [[ "$line" == *"[breaking]"* ]]; then
      echo "major"
      return
    fi

    # MINOR: new features (backwards-compatible additions)
    # - feat: or feat(scope):
    if [[ "$line" =~ ^feat(\(.+\))?: ]]; then
      has_feat=true
    fi
  done

  if [ "$has_feat" = true ]; then
    echo "minor"
  else
    echo "$bump"
  fi
}

BUMPED_PLUGINS=()

for plugin_dir in "$PLUGINS_DIR"/*/; do
  [ ! -d "$plugin_dir" ] && continue
  plugin_name=$(basename "$plugin_dir")
  plugin_json="$plugin_dir/.claude-plugin/plugin.json"

  # Validate plugin.json exists and has version
  if [ ! -f "$plugin_json" ]; then
    echo "ERROR: $plugin_name missing .claude-plugin/plugin.json" >&2
    exit 1
  fi

  current_version=$(jq -r '.version // empty' "$plugin_json")
  if [ -z "$current_version" ]; then
    echo "ERROR: $plugin_name plugin.json missing version field" >&2
    exit 1
  fi

  # Check if any files changed for this plugin since last bump
  changed_files=$(git -C "$REPO_ROOT" diff --name-only "$LAST_BUMP_SHA"..HEAD -- "plugins/$plugin_name/" 2>/dev/null || true)
  if [ -z "$changed_files" ]; then
    echo "  $plugin_name ($current_version): no changes — skipping"
    continue
  fi

  # Get commit messages (subject + body) touching this plugin since last bump.
  # Check both the published dir (plugins/) AND the source dir (plugin/) since
  # feat: commits typically land in source first and get synced as chore: commits.
  commits=$(git -C "$REPO_ROOT" log "$LAST_BUMP_SHA"..HEAD --pretty=format:"%s%n%b" -- "plugins/$plugin_name/" "plugin/" 2>/dev/null || true)
  if [ -z "$commits" ]; then
    echo "  $plugin_name ($current_version): no commits found — skipping"
    continue
  fi

  # Determine bump level
  bump=$(echo "$commits" | determine_bump)

  # Apply semver bump with proper resets
  IFS='.' read -r major minor patch <<< "$current_version"
  case "$bump" in
    major) new_version="$((major + 1)).0.0" ;;  # reset minor + patch
    minor) new_version="$major.$((minor + 1)).0" ;;  # reset patch
    patch) new_version="$major.$minor.$((patch + 1))" ;;
  esac

  # Show what triggered the bump
  echo "  $plugin_name: $current_version -> $new_version ($bump)"
  changed_count=$(echo "$changed_files" | wc -l)
  commit_count=$(git -C "$REPO_ROOT" log "$LAST_BUMP_SHA"..HEAD --oneline -- "plugins/$plugin_name/" 2>/dev/null | wc -l)
  echo "    $commit_count commit(s), $changed_count file(s) changed"

  # Update plugin.json
  tmp=$(mktemp)
  jq --arg v "$new_version" '.version = $v' "$plugin_json" > "$tmp" && mv "$tmp" "$plugin_json"

  # Update marketplace.json
  tmp=$(mktemp)
  jq --arg name "$plugin_name" --arg v "$new_version" \
    '(.plugins[] | select(.name == $name)).version = $v' \
    "$MARKETPLACE_JSON" > "$tmp" && mv "$tmp" "$MARKETPLACE_JSON"

  # Generate CHANGELOG.md — rolling log of last 50 versions
  changelog_file="$plugin_dir/CHANGELOG.md"
  {
    echo "# Changelog"
    echo ""
    echo "## $new_version ($(date -u +%Y-%m-%d))"
    echo ""
    git -C "$REPO_ROOT" log "$LAST_BUMP_SHA"..HEAD --pretty=format:"- %s" -- "plugins/$plugin_name/" 2>/dev/null \
      | grep -v "^- chore: auto-bump" || true
    echo ""

    # Append previous entries if changelog exists (keep last 50 versions)
    if [ -f "$changelog_file" ]; then
      # Skip the "# Changelog" header line and blank line
      tail -n +3 "$changelog_file" | head -500
    fi
  } > "${changelog_file}.tmp"
  mv "${changelog_file}.tmp" "$changelog_file"

  BUMPED_PLUGINS+=("$plugin_name@$new_version")
done

echo ""

if [ ${#BUMPED_PLUGINS[@]} -eq 0 ]; then
  echo "No plugins bumped."
  exit 0
fi

# Commit the version bumps
cd "$REPO_ROOT"
git add .claude-plugin/marketplace.json
for entry in "${BUMPED_PLUGINS[@]}"; do
  name="${entry%%@*}"
  git add "plugins/$name/.claude-plugin/plugin.json"
  git add "plugins/$name/CHANGELOG.md" 2>/dev/null || true
done

BUMP_MSG="chore: auto-bump"
for entry in "${BUMPED_PLUGINS[@]}"; do
  BUMP_MSG="$BUMP_MSG ${entry}"
done

git commit -m "$BUMP_MSG"
echo "Committed: $BUMP_MSG"
