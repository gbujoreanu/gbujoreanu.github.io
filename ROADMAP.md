# Done

- App directory and GitHub Pages deployment.
- Shared authentication, email verification, current password-reset flow, and sessions.
- Account profiles: editable names/handles, bio, discoverability, private avatars, and initials fallback.
- Shared Apps/Profile controls and app marks; independent app settings and five themes per app.
- Daymark: tasks, goals, Calendar, and the daily Scheduler with saved schedule entries.
- Fairway: courses, individual rounds, score entry/review, history, statistics, and first-use guidance.
- Money: budgeting, transactions, bills, earnings/paychecks, savings, retirement, assets/net worth, and reports.
- Connections and Fairway Friends relationship foundation: discovery, follows/followers, friend requests, friendships, and blocking. Shared search reliability remains the Ready task.
- Account Family household/invitation/membership foundation: creation, invitations, membership management, leaving, and deletion. Further validation and changes remain possible.
- Connections and Family type-ahead search with eligibility states; reliability fixes remain in Ready.
- Fairway planned rounds, friend invitations, host controls, and participant responses.
- Fairway group scorecards: participant/self scoring, host scoring, incremental saves, mobile hole navigation, and completion. Personal-history/handicap linkage is not included.
- Existing Supabase migrations, RLS protections, and regression-test coverage.

# Ready

## New-user profile provisioning and shared search fix

- Repair missing/incomplete existing profiles safely.
- Ensure new users reliably receive usable profiles.
- Support permanent fallback User### identities where needed.
- Preserve chosen names, handles, and avatars.
- Make Connections search reliable.
- Make Family search reliable.
- Make eligible new users searchable.
- Preserve discoverability, blocking, RLS, and email privacy.

# Backlog

These are high-level items, not final specifications. The user may change, remove, reorder, or redesign them later. Implement only an explicitly selected Ready task.

- Validate/fix remaining Family basic functionality with real accounts.
- Fairway Friends / rounds / scorecard changes based on user testing.
- Fairway completed shared rounds → personal history/handicap.
- Fairway scorecard sharing/export.
- Fairway → Daymark Calendar/Scheduler integration.
- Daymark Family sharing.
- Money → Daymark bill due dates and later carefully scoped household features.
- Dedicated password recovery/change-password flow.
- Authentication redirect/security audit.
- Standard automated test/CI workflow.
- Private Admin/System Health portal.
- Rich link previews.
- Final app-specific UX/security/performance passes.
