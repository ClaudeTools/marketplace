#!/usr/bin/env python3
"""Validate memory system file structure and format.

Checks:
  - generated.md section structure
  - developer-edits.md numbered list format
  - config.yaml required fields
  - history.jsonl valid JSON per line

Exit 0 if valid, 1 if any errors. Prints errors and warnings.
"""

import json
import os
import sys
from pathlib import Path

MEMORY_DIR = Path.home() / ".claude" / "memory"

REQUIRED_CONFIG_FIELDS = {
    "enabled",
    "auto_generate",
    "max_generated_tokens",
    "max_developer_edits",
    "max_edit_length",
    "injection_mode",
    "summariser_model",
}

REQUIRED_GENERATED_SECTIONS = [
    "Work context",
    "Personal context",
    "Top of mind",
    "Brief history",
]

errors: list[str] = []
warnings: list[str] = []


def validate_generated_md() -> None:
    """Validate generated.md has the required section structure."""
    path = MEMORY_DIR / "generated.md"
    if not path.exists():
        warnings.append("generated.md does not exist (not yet generated)")
        return

    content = path.read_text(encoding="utf-8")
    for section in REQUIRED_GENERATED_SECTIONS:
        # Sections can be ## or ### headings
        if section not in content:
            errors.append(f"generated.md missing required section: '{section}'")


def validate_developer_edits() -> None:
    """Validate developer-edits.md uses numbered list format."""
    path = MEMORY_DIR / "developer-edits.md"
    if not path.exists():
        warnings.append("developer-edits.md does not exist (no developer entries yet)")
        return

    content = path.read_text(encoding="utf-8")
    lines = [line for line in content.strip().splitlines() if line.strip()]

    if not lines:
        warnings.append("developer-edits.md is empty")
        return

    expected_num = 1
    for i, line in enumerate(lines):
        stripped = line.strip()
        # Allow comment lines and blank lines
        if stripped.startswith("#") or not stripped:
            continue
        # Check numbered list format: "1. content" or "1) content"
        valid_dot = stripped.startswith(f"{expected_num}.")
        valid_paren = stripped.startswith(f"{expected_num})")
        if valid_dot or valid_paren:
            expected_num += 1
        else:
            errors.append(
                f"developer-edits.md line {i + 1}: expected entry {expected_num}, "
                f"got '{stripped[:40]}...'"
            )
            # Try to recover by checking if it matches any number
            for n in range(1, 1000):
                if stripped.startswith(f"{n}.") or stripped.startswith(f"{n})"):
                    expected_num = n + 1
                    break


def validate_config() -> None:
    """Validate config.yaml has all required fields."""
    path = MEMORY_DIR / "config.yaml"
    if not path.exists():
        errors.append("config.yaml does not exist — memory system not configured")
        return

    content = path.read_text(encoding="utf-8")

    # Simple YAML parsing without external deps — check for key presence
    found_fields: set[str] = set()
    for line in content.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            # Extract the key before the first colon
            if ":" in stripped:
                key = stripped.split(":", 1)[0].strip()
                found_fields.add(key)

    missing = REQUIRED_CONFIG_FIELDS - found_fields
    if missing:
        for field in sorted(missing):
            errors.append(f"config.yaml missing required field: '{field}'")


def validate_history() -> None:
    """Validate history.jsonl has valid JSON per line."""
    path = MEMORY_DIR / "history.jsonl"
    if not path.exists():
        warnings.append("history.jsonl does not exist (no history yet)")
        return

    content = path.read_text(encoding="utf-8")
    lines = content.strip().splitlines()

    if not lines:
        warnings.append("history.jsonl is empty")
        return

    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            obj = json.loads(stripped)
            if not isinstance(obj, dict):
                errors.append(
                    f"history.jsonl line {i + 1}: expected JSON object, got {type(obj).__name__}"
                )
        except json.JSONDecodeError as e:
            errors.append(f"history.jsonl line {i + 1}: invalid JSON — {e}")


def main() -> int:
    print(f"Validating memory system at: {MEMORY_DIR}")
    print()

    if not MEMORY_DIR.exists():
        print("ERROR: Memory directory does not exist: ~/.claude/memory/")
        print("Run setup to initialise the memory system.")
        return 1

    validate_generated_md()
    validate_developer_edits()
    validate_config()
    validate_history()

    if errors:
        print(f"ERRORS ({len(errors)}):")
        for err in errors:
            print(f"  ✗ {err}")
        print()

    if warnings:
        print(f"WARNINGS ({len(warnings)}):")
        for warn in warnings:
            print(f"  ⚠ {warn}")
        print()

    if not errors and not warnings:
        print("All checks passed. Memory system is valid.")
    elif not errors:
        print("No errors. Warnings above are informational.")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
