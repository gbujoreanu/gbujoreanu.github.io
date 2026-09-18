# Development and validation

## Scope before code

Read `AGENTS.md`, inspect the relevant implementation, and keep each change focused. Do not weaken database authorization to simplify frontend work.

## Frontend checks

Run the JavaScript tests:

```sh
node --test tracker/scheduler.test.js tracker/fairway-events.test.js shared/profile-discovery.test.mjs money/calculations.test.js
```

Check changed JavaScript files with `node --check`. For user-facing work, also exercise the deployed workflow on desktop and mobile where practical; automated checks do not prove that real browser interactions work.

## Database checks

For a Supabase change:

1. create a new version-controlled migration;
2. preserve existing data;
3. verify constraints, indexes, grants, RLS, triggers, and function `search_path`;
4. test authenticated User A, authenticated User B, and anonymous access;
5. run the relevant transactional SQL test from `supabase/tests/`;
6. run Supabase security and performance advisors when available.

Never put privileged Supabase credentials in GitHub Actions for untrusted pull-request execution.
