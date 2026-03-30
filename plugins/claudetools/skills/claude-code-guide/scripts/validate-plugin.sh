#!/usr/bin/env bash
# validate-plugin.sh — Check a plugin directory follows Claude Code best practices
# Usage: bash validate-plugin.sh /path/to/plugin-directory
set -euo pipefail

PLUGIN_DIR="${1:-}"
if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR" ]; then
  echo "Usage: bash validate-plugin.sh /path/to/plugin-directory"
  exit 1
fi

# shellcheck source=lib/validator-framework.sh
source "$(dirname "$0")/lib/validator-framework.sh"

DIRNAME=$(basename "$PLUGIN_DIR")
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"

echo "=== Validating plugin: $DIRNAME ==="

# --- Structure ---
echo "--- Structure ---"

if [ ! -f "$MANIFEST" ]; then
  vf_fail ".claude-plugin/plugin.json not found"
  vf_summary
  vf_exit
fi
vf_pass ".claude-plugin/plugin.json exists"

# Validate JSON
JSON_VALID=false
if command -v jq &>/dev/null; then
  if jq . "$MANIFEST" > /dev/null 2>&1; then
    vf_pass "plugin.json is valid JSON (jq)"
    JSON_VALID=true
  else
    vf_fail "plugin.json is not valid JSON"
  fi
elif command -v python3 &>/dev/null; then
  if python3 -c "import json; json.load(open('$MANIFEST'))" 2>/dev/null; then
    vf_pass "plugin.json is valid JSON (python3)"
    JSON_VALID=true
  else
    vf_fail "plugin.json is not valid JSON"
  fi
else
  vf_warn "neither jq nor python3 available — skipping JSON content checks"
fi

# --- Manifest ---
vf_section "Manifest"

if [ "$JSON_VALID" = true ]; then
  # Helper to extract a field value from JSON
  json_field() {
    local field="$1"
    if command -v jq &>/dev/null; then
      jq -r ".$field // empty" "$MANIFEST" 2>/dev/null
    else
      python3 -c "import json; d=json.load(open('$MANIFEST')); v=d.get('$field',''); print(v if v else '')" 2>/dev/null
    fi
  }

  # name
  NAME=$(json_field name)
  if [ -n "$NAME" ]; then
    vf_pass "name field present: $NAME"
  else
    vf_fail "missing 'name' field in plugin.json"
  fi

  # version
  VERSION=$(json_field version)
  if [ -n "$VERSION" ]; then
    vf_pass "version field present: $VERSION"
    if echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      vf_pass "version matches semver pattern (X.Y.Z)"
    else
      vf_fail "version '$VERSION' does not match semver pattern X.Y.Z"
    fi
  else
    vf_fail "missing 'version' field in plugin.json"
  fi

  # description
  DESC=$(json_field description)
  if [ -n "$DESC" ]; then
    vf_pass "description field present"
  else
    vf_fail "missing 'description' field in plugin.json"
  fi

  # author (warn only)
  AUTHOR=""
  if command -v jq &>/dev/null; then
    AUTHOR=$(jq -r 'if .author | type == "object" then .author.name // empty elif .author then .author else empty end' "$MANIFEST" 2>/dev/null || true)
  else
    AUTHOR=$(json_field author)
  fi
  if [ -n "$AUTHOR" ]; then
    vf_pass "author field present: $AUTHOR"
  else
    vf_warn "missing 'author' field in plugin.json"
  fi

  # keywords (warn only)
  KEYWORDS=""
  if command -v jq &>/dev/null; then
    KEYWORDS=$(jq -r '.keywords // empty | if type == "array" then .[0] // empty else . end' "$MANIFEST" 2>/dev/null || true)
  else
    KEYWORDS=$(python3 -c "import json; d=json.load(open('$MANIFEST')); k=d.get('keywords',[]); print(k[0] if k else '')" 2>/dev/null || true)
  fi
  if [ -n "$KEYWORDS" ]; then
    vf_pass "keywords field present"
  else
    vf_warn "missing 'keywords' field in plugin.json"
  fi
else
  vf_warn "skipping manifest field checks — JSON could not be parsed"
fi

# --- Components ---
vf_section "Components"

# hooks/hooks.json
HOOKS_JSON="$PLUGIN_DIR/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  vf_pass "hooks/hooks.json exists"
  HOOKS_VALID=false
  if command -v jq &>/dev/null; then
    if jq . "$HOOKS_JSON" > /dev/null 2>&1; then
      vf_pass "hooks.json is valid JSON"
      HOOKS_VALID=true
    else
      vf_fail "hooks.json is not valid JSON"
    fi
  elif command -v python3 &>/dev/null; then
    if python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null; then
      vf_pass "hooks.json is valid JSON"
      HOOKS_VALID=true
    else
      vf_fail "hooks.json is not valid JSON"
    fi
  else
    vf_warn "cannot validate hooks.json — no JSON parser available"
  fi
fi

# skills/ directory
if [ -d "$PLUGIN_DIR/skills" ]; then
  while IFS= read -r skill_dir; do
    SKILL_NAME=$(basename "$skill_dir")
    if [ -f "$skill_dir/SKILL.md" ]; then
      vf_pass "skill '$SKILL_NAME' has SKILL.md"
    else
      vf_fail "skill '$SKILL_NAME' missing SKILL.md"
    fi
  done < <(find "$PLUGIN_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# agents/ directory
if [ -d "$PLUGIN_DIR/agents" ]; then
  while IFS= read -r agent_file; do
    AGENT_NAME=$(basename "$agent_file")
    if head -1 "$agent_file" | grep -q '^---$'; then
      vf_pass "agent '$AGENT_NAME' has frontmatter"
    else
      vf_fail "agent '$AGENT_NAME' missing frontmatter (must start with ---)"
    fi
  done < <(find "$PLUGIN_DIR/agents" -name "*.md" 2>/dev/null)
fi

# mcpServers — check referenced start scripts
if [ "$JSON_VALID" = true ]; then
  MCP_PATHS=""
  if command -v jq &>/dev/null; then
    MCP_PATHS=$(jq -r '.mcpServers // {} | to_entries[] | .value.command // empty, (.value.args // [] | .[])' "$MANIFEST" 2>/dev/null | grep -E '\.sh$|\.js$|\.mjs$' || true)
  elif command -v python3 &>/dev/null; then
    MCP_PATHS=$(python3 -c "
import json
d = json.load(open('$MANIFEST'))
for k, v in d.get('mcpServers', {}).items():
    cmd = v.get('command', '')
    if cmd: print(cmd)
    for a in v.get('args', []):
        if isinstance(a, str): print(a)
" 2>/dev/null | grep -E '\.sh$|\.js$|\.mjs$' || true)
  fi

  if [ -n "$MCP_PATHS" ]; then
    while IFS= read -r mcp_path; do
      # Resolve ${CLAUDE_PLUGIN_ROOT} to the plugin directory
      resolved=$(echo "$mcp_path" | sed "s|\${CLAUDE_PLUGIN_ROOT}|$PLUGIN_DIR|g; s|\$CLAUDE_PLUGIN_ROOT|$PLUGIN_DIR|g")
      if [ -f "$resolved" ]; then
        vf_pass "MCP script exists: $(basename "$resolved")"
      else
        vf_fail "MCP script missing: $mcp_path"
      fi
    done <<< "$MCP_PATHS"
  fi
fi

# --- Hygiene ---
vf_section "Hygiene"

if [ -d "$PLUGIN_DIR/node_modules" ]; then
  vf_fail "node_modules/ directory present — should not be committed"
else
  vf_pass "no node_modules/ directory"
fi

if [ -d "$PLUGIN_DIR/logs" ]; then
  vf_warn "logs/ directory present — consider adding to .gitignore"
else
  vf_pass "no logs/ directory"
fi

if [ -f "$PLUGIN_DIR/README.md" ]; then
  vf_pass "README.md exists"
else
  vf_warn "no README.md — consider adding one for documentation"
fi

vf_summary
vf_exit
