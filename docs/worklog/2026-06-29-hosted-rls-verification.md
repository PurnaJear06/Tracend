# Worklog: 2026-06-29 Hosted RLS Verification

## Result

- Ran the existing `user_accounts` pgTAP behavior suite against hosted project
  `qsfzzsjenopqqqhvpyaw` through the Supabase SQL Editor.
- Collected all assertions into a transaction-local temporary result table so
  the editor displayed every outcome.
- Result: **8/8 passed**.

## Verified Behavior

1. RLS is enabled.
2. RLS is forced.
3. An authenticated user reads only their account.
4. An authenticated user can update their account.
5. The own-account update persists.
6. An update increments `row_version`.
7. A cross-user update changes no row.
8. A user cannot insert an account for another identity.

The script ran inside `BEGIN` / `ROLLBACK`; all synthetic Auth users, account
rows, updates, and the temporary result table were removed automatically.
A follow-up hosted query returned `synthetic_rows_remaining = 0`.
