# Code Review Checklist

## Pass 1: Correctness
- [ ] Logic matches stated intent (commit message, PR description)
- [ ] Null/undefined/empty checks on inputs and returns
- [ ] Boundary values handled (0, -1, MAX_INT, empty string)
- [ ] Error paths return or throw (no silent swallowing)
- [ ] Async/await used correctly (no floating promises)
- [ ] Types are explicit (no implicit any, correct generics)
- [ ] State mutations are intentional and consistent
- [ ] Conditionals cover all branches

## Pass 2: Security
- [ ] No string interpolation in SQL/queries (use parameterised)
- [ ] User input sanitised before HTML/JSX rendering
- [ ] No hardcoded secrets, keys, tokens, or passwords
- [ ] File paths validated (no path traversal via ../)
- [ ] Auth/authz checks on all sensitive endpoints
- [ ] CORS and CSP headers configured correctly
- [ ] Sensitive data not logged or exposed in errors

## Pass 3: Performance
- [ ] No N+1 queries (batch or join instead)
- [ ] Database queries use appropriate indexes
- [ ] Loops are bounded (no unbounded recursion)
- [ ] No large allocations in hot paths or loops
- [ ] List endpoints paginated
- [ ] Expensive operations cached where appropriate
- [ ] No blocking I/O in async contexts

## Pass 4: Maintainability
- [ ] Follows existing codebase patterns and conventions
- [ ] Names are descriptive and consistent
- [ ] No copy-paste duplication (extract shared logic)
- [ ] Tests added or updated for changed behaviour
- [ ] Public APIs documented
- [ ] No dead code or commented-out blocks
- [ ] Functions are single-purpose and reasonably sized
