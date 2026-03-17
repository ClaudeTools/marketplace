#!/usr/bin/env python3
"""Report memory system statistics.

Reports:
  - Last generated timestamp
  - Generation count
  - Developer edit count
  - Estimated injection token count
  - Config status
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

MEMORY_DIR = Path.home() / ".claude" / "memory"


def get_last_generated_timestamp() -> str:
    """Get timestamp of last 'regenerated' entry from history.jsonl."""
    path = MEMORY_DIR / "history.jsonl"
    if not path.exists():
        return "never"

    last_ts = None
    for line in path.read_text(encoding="utf-8").strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if obj.get("action") == "regenerated" and "timestamp" in obj:
                last_ts = obj["timestamp"]
        except (json.JSONDecodeError, AttributeError):
            continue

    return last_ts if last_ts else "never"


def get_generation_count() -> int:
    """Count 'regenerated' entries in history.jsonl."""
    path = MEMORY_DIR / "history.jsonl"
    if not path.exists():
        return 0

    count = 0
    for line in path.read_text(encoding="utf-8").strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if obj.get("action") == "regenerated":
                count += 1
        except (json.JSONDecodeError, AttributeError):
            continue

    return count


def get_developer_edit_count() -> int:
    """Count entries in developer-edits.md."""
    path = MEMORY_DIR / "developer-edits.md"
    if not path.exists():
        return 0

    count = 0
    for line in path.read_text(encoding="utf-8").strip().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Match numbered entries: "1. text" or "1) text"
        for n in range(1, 1000):
            if stripped.startswith(f"{n}.") or stripped.startswith(f"{n})"):
                count += 1
                break

    return count


def get_estimated_tokens() -> int:
    """Estimate injection token count from memory-context.md (chars / 4)."""
    path = MEMORY_DIR / "memory-context.md"
    if not path.exists():
        return 0

    content = path.read_text(encoding="utf-8")
    return len(content) // 4


def get_config_status() -> dict:
    """Read key config values."""
    path = MEMORY_DIR / "config.yaml"
    if not path.exists():
        return {"exists": False}

    result = {"exists": True}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()
            if key in ("enabled", "auto_generate", "injection_mode"):
                result[key] = value

    return result


def main() -> None:
    print("Memory System Status")
    print("=" * 40)
    print()

    if not MEMORY_DIR.exists():
        print("Memory directory not found: ~/.claude/memory/")
        print("Run setup to initialise the memory system.")
        sys.exit(1)

    # Last generated
    last_ts = get_last_generated_timestamp()
    print(f"Last generated:       {last_ts}")

    # Generation count
    gen_count = get_generation_count()
    print(f"Generation count:     {gen_count}")

    # Developer edit count
    edit_count = get_developer_edit_count()
    print(f"Developer entries:    {edit_count}")

    # Estimated tokens
    est_tokens = get_estimated_tokens()
    print(f"Est. injection tokens: {est_tokens:,}")

    print()

    # Config status
    config = get_config_status()
    if not config["exists"]:
        print("Config:               NOT FOUND")
    else:
        print("Config:")
        print(f"  enabled:            {config.get('enabled', 'not set')}")
        print(f"  auto_generate:      {config.get('auto_generate', 'not set')}")
        print(f"  injection_mode:     {config.get('injection_mode', 'not set')}")

    print()

    # File existence check
    print("Files:")
    files = [
        "config.yaml",
        "developer-edits.md",
        "generated.md",
        "memory-context.md",
        "history.jsonl",
    ]
    for f in files:
        path = MEMORY_DIR / f
        status = "exists" if path.exists() else "missing"
        size = ""
        if path.exists():
            size = f" ({path.stat().st_size:,} bytes)"
        print(f"  {f:<25} {status}{size}")


if __name__ == "__main__":
    main()
