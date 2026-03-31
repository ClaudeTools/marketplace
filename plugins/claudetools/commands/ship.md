---
description: "Finish the development branch — merge, PR, or cleanup. Updates docs if needed."
argument-hint: "[merge|pr|cleanup]"
---

This is a workflow command. Follow this sequence:
1. Invoke the `claudetools:verify` skill to confirm all tests pass and work is clean
2. Invoke the `claudetools:finish` skill to merge, create PR, or cleanup
3. If docs were changed, also invoke `claudetools:docs-manager` with argument "reindex"
