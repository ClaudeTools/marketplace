#!/usr/bin/env bash
# detect-project.sh
# Universal project type detection. Source from hook scripts.
# Usage: source "$(dirname "$0")/lib/detect-project.sh" && detect_project_type
#
# Sets PROJECT_TYPE to one of:
#   node, python, rust, go, java, dotnet, ruby, swift, general
#
# Functions:
#   detect_project_type  — detect and set PROJECT_TYPE
#   is_code_project      — returns 0 for code projects, 1 for general

PROJECT_TYPE=""

detect_project_type() {
  local dir="${1:-$(pwd)}"

  # Walk up from dir looking for project markers
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/package.json" ]; then
      PROJECT_TYPE="node"
      return 0
    elif [ -f "$dir/Cargo.toml" ]; then
      PROJECT_TYPE="rust"
      return 0
    elif [ -f "$dir/go.mod" ]; then
      PROJECT_TYPE="go"
      return 0
    elif [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/requirements.txt" ]; then
      PROJECT_TYPE="python"
      return 0
    elif [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
      PROJECT_TYPE="java"
      return 0
    elif find "$dir" -maxdepth 1 -name '*.csproj' -o -name '*.sln' 2>/dev/null | grep -q .; then
      PROJECT_TYPE="dotnet"
      return 0
    elif [ -f "$dir/Gemfile" ]; then
      PROJECT_TYPE="ruby"
      return 0
    elif [ -f "$dir/Package.swift" ]; then
      PROJECT_TYPE="swift"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  PROJECT_TYPE="general"
  return 0
}

is_code_project() {
  if [ -z "$PROJECT_TYPE" ]; then
    detect_project_type
  fi
  [ "$PROJECT_TYPE" != "general" ]
}
