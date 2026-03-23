# Example Review Output

## Code Review: src/api/users.ts

### Critical (must fix)
- [src/api/users.ts:42] SQL injection via string interpolation in `findUser()`. Use parameterised query instead of template literal.
- [src/api/users.ts:87] Missing auth middleware on DELETE /users/:id endpoint. Any authenticated user can delete other users.

### Important (should fix)
- [src/api/users.ts:23] `getUserById` swallows database errors silently — returns undefined on both "not found" and "connection failed". Rethrow non-404 errors.
- [src/api/users.ts:61] Unbounded `SELECT *` on users table with no pagination. Add limit/offset or cursor-based pagination.

### Suggestions (nice to have)
- [src/api/users.ts:15] `userData` type could use the existing `UserDTO` interface from `src/types/user.ts` instead of inline type.
- [src/api/users.ts:95] Extract the email validation regex into a shared util — same pattern exists in `src/api/auth.ts:31`.

### Positive
- Clean separation of route handlers and business logic.
- Consistent error response format using the shared `ApiError` class.
- Good use of TypeScript discriminated unions for user roles.
