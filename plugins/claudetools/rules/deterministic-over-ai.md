---
paths:
  - "**/*"
---

# Deterministic Tooling Over AI Inference

Everything follows one principle: if a shell command, script, linter, type-checker, build tool, test runner, hook, or any non-AI mechanism can do it — use that. AI inference is only for what requires judgment.

## When to Use Deterministic Tooling
- File operations (rename, search-replace, bulk imports) → Bash/sed/grep
- Verification → runnable commands (tests, typecheck, grep, curl, exit codes)
- Documentation lookup → WebSearch, Context7, platform docs
- Code search → Grep, Glob, LSP tools
- Deployment → CLI commands (wrangler, vercel, gh, fly, railway)
- Quality checks → hooks enforce automatically, don't re-check with AI
- Counting/measuring → wc, du, find, jq

## When to Use AI Inference
- Code generation (writing new functions, components, logic)
- Architectural reasoning (design decisions, tradeoffs)
- Complex debugging (understanding why something fails)
- Content writing (prompts, documentation, user-facing text)
- Pattern recognition (identifying code smells across files)

## Never
- Never use AI to "review and confirm it looks correct" — run the checker
- Never use AI to count files or measure sizes — use du/wc/find
- Never use AI to search code — use Grep/Glob
- Never use AI to verify a deploy worked — use curl/Chrome
- Never guess what a project needs — read the code
- Never create agents for work that doesn't need doing
