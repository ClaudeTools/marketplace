#!/bin/bash
# Shared library: code quality pattern detection
# Provides stub, type-abuse, and ts-suppress counting functions for validators.
# All functions: take a file path, echo an integer count, return 0.
# Missing or unreadable files are treated as 0 matches.

# count_stubs_in_file FILE_PATH
# Counts stub/TODO/placeholder patterns across multiple languages.
# Covers: TODO/FIXME/STUB/PLACEHOLDER comments, throw new Error("not implemented"),
# NotImplementedError, Python pass, Rust todo!/unimplemented!, empty function bodies,
# hardcoded-return stub bodies (return null/undefined/{}/[]).
count_stubs_in_file() {
  local file="$1"
  [ -z "$file" ] || [ ! -f "$file" ] && echo 0 && return 0

  local comment_stubs empty_bodies
  comment_stubs=$(grep -cE \
    'throw new Error\(.*(not implemented|todo|fixme|placeholder)|//\s*(TODO|FIXME|HACK|STUB|PLACEHOLDER):?\s|#\s*(TODO|FIXME|STUB|PLACEHOLDER):?\s|NotImplementedError|\btodo!\(\)|\bunimplemented!\(\)|\bpass\s*$' \
    "$file" 2>/dev/null || true)
  empty_bodies=$(grep -cE \
    'function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*\}|function\s+[a-zA-Z0-9_]+\([^)]*\)\s*\{\s*return\s+(null|undefined|\{\}|\[\])' \
    "$file" 2>/dev/null || true)

  echo $(( ${comment_stubs:-0} + ${empty_bodies:-0} ))
  return 0
}

# count_type_abuse FILE_PATH
# Counts TypeScript type-abuse patterns: "as any" and ": any" usages.
count_type_abuse() {
  local file="$1"
  [ -z "$file" ] || [ ! -f "$file" ] && echo 0 && return 0

  local any_count
  any_count=$(grep -co 'as any\b\|: any\b' "$file" 2>/dev/null || true)

  echo "${any_count:-0}"
  return 0
}

# count_unknown_as FILE_PATH
# Counts "as unknown as" double-cast circumvention patterns.
# These bypass type safety the same way "as any" does.
count_unknown_as() {
  local file="$1"
  [ -z "$file" ] || [ ! -f "$file" ] && echo 0 && return 0

  local count
  count=$(grep -co 'as unknown as\b' "$file" 2>/dev/null || true)

  echo "${count:-0}"
  return 0
}

# count_ts_ignores FILE_PATH
# Counts TypeScript suppression directives: @ts-ignore and @ts-expect-error.
count_ts_ignores() {
  local file="$1"
  [ -z "$file" ] || [ ! -f "$file" ] && echo 0 && return 0

  local count
  count=$(grep -cE '@ts-ignore|@ts-expect-error' "$file" 2>/dev/null || true)

  echo "${count:-0}"
  return 0
}
