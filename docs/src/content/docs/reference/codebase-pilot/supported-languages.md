---
title: "Supported Languages"
description: "Supported Languages — claudetools documentation."
---
Codebase Pilot supports 14 languages via tree-sitter parsing.

## Native (compiled bindings)

These parse synchronously with zero latency:

| Language | File extensions |
|----------|----------------|
| TypeScript | `.ts`, `.tsx` |
| JavaScript | `.js`, `.jsx`, `.mjs`, `.cjs` |
| Python | `.py` |

## WASM (lazy-loaded)

These load asynchronously on first use:

| Language | File extensions |
|----------|----------------|
| Go | `.go` |
| Rust | `.rs` |
| Java | `.java` |
| Kotlin | `.kt`, `.kts` |
| Ruby | `.rb` |
| C# | `.cs` |
| PHP | `.php` |
| Swift | `.swift` |
| C | `.c`, `.h` |
| C++ | `.cpp`, `.hpp`, `.cc`, `.cxx` |
| Bash | `.sh` |

## What gets extracted

For all languages, the parser extracts:

- **Symbols**: functions, classes, interfaces, types, enums, variables, methods, properties
- **Imports**: import sources and imported symbol names
- **Hierarchy**: class members linked to parent classes via `parent_id`
- **Signatures**: full function/method signatures with parameters and return types
- **Export status**: whether each symbol is exported

## Installing WASM grammars

Native grammars install with `npm install`. WASM grammars need a separate download:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/codebase-pilot/scripts/download-grammars.sh
```

Run `codebase-pilot doctor` to check which grammars are available.
