---
paths:
  - "package.json"
  - "Cargo.toml"
  - "pyproject.toml"
  - "go.mod"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.rs"
  - "**/*.go"
---
## Project Verification Commands

Detect the project type from config files and use the appropriate commands:

| Config File | Typecheck | Test | Lint |
|-------------|-----------|------|------|
| package.json (TypeScript) | `npx tsc --noEmit` | `npm test` | `npx eslint .` |
| Cargo.toml | `cargo check` | `cargo test` | `cargo clippy` |
| pyproject.toml / setup.py | `mypy .` | `pytest` | `ruff check .` |
| go.mod | `go vet ./...` | `go test ./...` | `golangci-lint run` |

Read the project's config file to determine which row applies. Run typecheck after each change. Run tests before committing.
