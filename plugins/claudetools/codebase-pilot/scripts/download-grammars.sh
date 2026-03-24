#!/usr/bin/env bash
# Download WASM grammars for languages detected in a project.
# Usage: download-grammars.sh [project_root]
# Idempotent — skips grammars already cached.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAMMAR_DIR="$(dirname "$SCRIPT_DIR")/grammars"
PROJECT_ROOT="${1:-$(pwd)}"

CDN_BASE="https://unpkg.com/tree-sitter-wasms@latest/out"

mkdir -p "$GRAMMAR_DIR"

# Detect languages from project config files and extensions
declare -A LANG_MAP
detect_languages() {
  local root="$1"

  [[ -f "$root/go.mod" || -f "$root/go.sum" ]] && LANG_MAP[go]=1
  [[ -f "$root/Cargo.toml" || -f "$root/Cargo.lock" ]] && LANG_MAP[rust]=1
  [[ -f "$root/pom.xml" || -f "$root/build.gradle" ]] && LANG_MAP[java]=1
  [[ -f "$root/build.gradle.kts" ]] && LANG_MAP[kotlin]=1
  [[ -f "$root/Gemfile" ]] && LANG_MAP[ruby]=1
  [[ -f "$root/composer.json" ]] && LANG_MAP[php]=1
  [[ -f "$root/Package.swift" ]] && LANG_MAP[swift]=1
  [[ -f "$root/CMakeLists.txt" || -f "$root/Makefile" ]] && LANG_MAP[c]=1

  # Extension-based detection (shallow scan — maxdepth 3)
  if find "$root" -maxdepth 3 -name "*.java" -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[java]=1
  fi
  if find "$root" -maxdepth 3 -name "*.kt" -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[kotlin]=1
  fi
  if find "$root" -maxdepth 3 -name "*.rb" -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[ruby]=1
  fi
  if find "$root" -maxdepth 3 \( -name "*.cs" -o -name "*.csproj" -o -name "*.sln" \) -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[c_sharp]=1
  fi
  if find "$root" -maxdepth 3 -name "*.c" -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[c]=1
  fi
  if find "$root" -maxdepth 3 \( -name "*.cpp" -o -name "*.hpp" -o -name "*.cc" \) -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[cpp]=1
  fi

  # Bash is always present (shell scripts exist in most projects)
  if find "$root" -maxdepth 3 -name "*.sh" -not -path "*/node_modules/*" -print -quit 2>/dev/null | grep -q .; then
    LANG_MAP[bash]=1
  fi
}

detect_languages "$PROJECT_ROOT"

if [[ ${#LANG_MAP[@]} -eq 0 ]]; then
  exit 0
fi

downloaded=0
skipped=0

for lang in "${!LANG_MAP[@]}"; do
  wasm_file="tree-sitter-${lang}.wasm"
  dest="$GRAMMAR_DIR/$wasm_file"

  if [[ -f "$dest" ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  url="$CDN_BASE/$wasm_file"
  if curl -fsSL --max-time 10 -o "$dest" "$url" 2>/dev/null; then
    downloaded=$((downloaded + 1))
  else
    rm -f "$dest" 2>/dev/null || true
  fi
done

if [[ $downloaded -gt 0 ]]; then
  echo "codebase-pilot: downloaded $downloaded WASM grammar(s), $skipped cached" >&2
fi
