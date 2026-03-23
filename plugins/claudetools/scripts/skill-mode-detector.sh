#!/usr/bin/env bash
# skill-mode-detector.sh — Classify task complexity from user prompt text.
#
# Reads the user's prompt from stdin and outputs "build" or "maintain".
#
# Build mode: new feature, creative work, design from scratch, redesign.
# Maintain mode: fix, wire, refactor, debug, update existing code.
#
# Usage:
#   echo "fix the login button alignment" | bash skill-mode-detector.sh
#   # outputs: maintain
#
#   echo "create a new landing page for the product" | bash skill-mode-detector.sh
#   # outputs: build

set -euo pipefail

# Read prompt from stdin (lowercase for matching)
prompt="$(cat | tr '[:upper:]' '[:lower:]')"

if [[ -z "$prompt" ]]; then
  echo "maintain"
  exit 0
fi

# --- Indicator word lists ---

# Build indicators: signals new/creative work
build_words=(
  "create"
  "design"
  "new"
  "build"
  "from scratch"
  "landing page"
  "redesign"
  "scaffold"
  "generate"
  "prototype"
  "mockup"
  "brand new"
  "greenfield"
  "initial"
  "set up"
  "setup"
  "bootstrap"
  "start fresh"
)

# Maintain indicators: signals work on existing code
maintain_words=(
  "fix"
  "wire"
  "connect"
  "update"
  "refactor"
  "debug"
  "change"
  "modify"
  "add to existing"
  "patch"
  "tweak"
  "adjust"
  "correct"
  "repair"
  "migrate"
  "move"
  "rename"
  "swap"
  "replace"
  "hook up"
  "integrate"
  "plug in"
  "bind"
  "link"
  "upgrade"
  "bump"
  "align"
)

build_score=0
maintain_score=0

for word in "${build_words[@]}"; do
  if [[ "$prompt" == *"$word"* ]]; then
    build_score=$((build_score + 1))
  fi
done

for word in "${maintain_words[@]}"; do
  if [[ "$prompt" == *"$word"* ]]; then
    maintain_score=$((maintain_score + 1))
  fi
done

# If the first argument to the skill was explicitly "build", override
if [[ "$prompt" == build* ]]; then
  echo "build"
  exit 0
fi

# Maintain wins ties — it's the conservative/cheaper choice
if [[ $build_score -gt $maintain_score ]]; then
  echo "build"
else
  echo "maintain"
fi
