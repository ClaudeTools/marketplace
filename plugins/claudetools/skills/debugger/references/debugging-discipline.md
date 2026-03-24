# Debugging Discipline Reference

## The 6-Step Protocol

1. **REPRODUCE** — Run the failing command. Capture exact error output.
2. **OBSERVE** — Read the code, recent changes, tests, and logs.
3. **HYPOTHESIZE** — State the cause with evidence. Rank if multiple.
4. **VERIFY** — Confirm root cause before writing any fix.
5. **FIX** — Fix the root cause. Add a regression test. Remove temp logging.
6. **CONFIRM** — Re-run the failing command, full test suite, and typecheck.

## Two-Strike Rule

- First fix fails: re-read error output, re-examine hypothesis.
- Second fix fails: stop. Add diagnostics, reproduce with verbose output, form a new hypothesis from scratch.
- Never attempt a third fix without fresh evidence.

## Common Anti-Patterns

- **Guessing** — Writing a fix without reproducing the bug or reading the error.
- **Symptom fixing** — Suppressing the error instead of fixing the cause.
- **Skipping reproduction** — Assuming you know what is wrong from the description alone.
- **Stack Overflow driven** — Copy-pasting a fix without understanding why it works.
- **Scatter-shot** — Changing multiple things at once so you cannot tell what fixed it.
- **No verification** — Declaring "fixed" without running the previously-failing command.
