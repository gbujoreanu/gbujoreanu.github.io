# Ecosystem Project Context

## Required workflow

Before making changes:

1. Read this file.
2. Inspect the relevant existing implementation before modifying it.
3. Inspect the relevant Supabase schema for database work.
4. Preserve the architecture, security boundaries, and existing user data.
5. Keep changes within the requested scope.
6. Test affected functionality.
7. Test deployed user-facing behavior when possible.
8. Update this file only when durable architecture, security, conventions, major capabilities, or roadmap status changes.

## Ecosystem and repositories

- `/`: public George Bujoreanu portfolio and project directory.
- `/account/`: shared authentication, identity, profile, security, and app-access hub.
- `/tracker/`: Daymark for tasks, goals, Calendar, and Scheduler.
- `/golf/`: Fairway for courses, rounds, scoring, statistics, and golf progress.
- `/money/`: private personal-finance tracking, budgeting, earnings, planning, assets, and reports.

The portfolio, Account, Daymark, Money, shared frontend code, and Supabase migrations live in this repository. Fairway is deployed at the same GitHub Pages origin but its source is maintained separately at `C:\Users\georg\Documents\Codex\golf`; inspect both repositories when work crosses that boundary.

## Architecture

- Static frontends are hosted with GitHub Pages; do not add a server unless a requirement truly needs one.
- Supabase provides shared authentication/session handling and the database.
- Browser-safe Supabase publishable/anon configuration may be public; privileged credentials may not.
- `/shared/` contains intentionally small shared platform code, including the Supabase client/session integration, metadata-driven App Switcher, theme-aware application marks, and shared profile/avatar rendering helper.
- Account/Profile is the neutral shared identity layer. Current profiles support display name, unique handle, bio, discoverability preference, initials fallback, and a private uploaded avatar.
- Schema changes belong in version-controlled files under `/supabase/migrations/`; database isolation tests belong under `/supabase/tests/`.
- Daymark, Fairway, and Money retain independent navigation, business logic, data authorization, settings, themes, and visual identities.

**The apps share an ecosystem, not their private application data or visual identity.**

## Security and privacy

- Supabase Row Level Security is the authorization boundary. Browser login gates are UX only.
- Never expose service-role keys, database passwords, secrets, private keys, or auth tokens.
- Never weaken RLS to make implementation easier.
- Preserve owner-only access for private application records and prevent forged ownership, ownership reassignment, IDOR, and cross-user references.
- Test authenticated User A against User B as well as anonymous access for every affected domain.
- Email is private. Any future discoverable profile must expose only deliberately safe fields, never email or private app records.
- Profile avatars use the private `avatars` Storage bucket. Object paths begin with the owning user's UUID, browser uploads are limited to JPG/PNG/WebP under 5 MB, and Storage policies restrict select/insert/update/delete to that owner path.
- Money data is always private. Daymark data is private unless a future feature explicitly shares a specific item.
- Friendship or discoverability must never automatically grant access to private application data.
- Preserve existing data and use non-destructive, version-controlled migrations.
- Do not store private application or financial records in localStorage. Local device UI preferences are acceptable.
- Review Supabase Auth security settings when relevant; leaked-password protection currently requires manual project configuration.

## UX and design principles

- Build modern consumer applications, not enterprise dashboards.
- Treat desktop and mobile as first-class experiences.
- Use progressive disclosure and avoid unnecessary complexity.
- Prefer semantic browser behavior and real links for normal navigation.
- Support keyboard use, visible focus, touch, screen readers, reduced motion, useful errors, and responsive layouts without horizontal overflow.
- Empty states should explain the next useful action. Do not add fake/sample data merely to fill a screen.
- Avoid placeholder branding, emoji as primary interface icons, and repetitive generic dashboard/card layouts.
- Validate real data, loading, empty, and failure states.

**Daymark, Fairway, and Money share design quality, not identical design.**

### Daymark

Daymark is calm and structured around time, planning, organization, timelines, and calendars. It includes Overview, Tasks, Goals, Calendar, Scheduler, Settings, five independent themes, and private Supabase persistence. Do not reduce every workflow to generic cards.

### Fairway

Fairway should feel like golf through scorecards, courses, round progression, and golf-specific hierarchy—not generic SaaS with green paint. It includes rounds, courses, scoring, statistics, Settings, and five independent themes.

The real-user UX/design pass is complete. Preserve these resulting conventions:

- Treat Add Round as a staged golf workflow with a scorecard and review, not a database form.
- Use the Fairway flag/course-contour mark and coherent SVG interface icons; avoid emoji in the core UI.
- New accounts start without courses or sample records, and first-use guidance leads from course setup to the first round.

### Money

Money covers Budget, Transactions, Bills, Earnings, Savings, Retirement, Assets/net worth, Reports, and Settings. Its governing principle is **simple and visual by default; powerful through drill-downs**. It should feel approachable rather than like accounting software, use decimal-safe calculations, and keep all financial records private in Supabase.

### Account

Account is the neutral ecosystem identity and authentication hub. It manages sign-up/sign-in, verified email, password reset, shared session, display name, handle, bio, discoverability preference, secure avatar upload/replace/remove, initials fallback, security actions, and access links to each app. Discoverability is currently a stored preference; public profile search/view is not implemented.

## User-facing testing

Automated tests alone do not prove that an interaction works. The desktop App Switcher bug demonstrated that source inspection and automation can miss actual deployed behavior.

For user-facing changes, when possible:

- Exercise the deployed GitHub Pages application and physically use the affected controls and navigation.
- Test desktop, tablet, and phone behavior.
- Refresh and verify session, data, and preference persistence.
- Check runtime and console errors.
- Distinguish automated checks from deployed manual user-flow testing.
- If an interaction cannot be faithfully verified, state that limitation rather than claiming it passed.

## Database workflow

For database changes:

1. Inspect the current schema and migrations.
2. Create a version-controlled migration.
3. Preserve existing data.
4. Review constraints and foreign keys, including cross-owner references and deletion behavior.
5. Review indexes.
6. Review grants.
7. Review and test RLS.
8. Review functions and triggers; restrict privileged functions and fix their `search_path`.
9. Test User A, User B, and anonymous isolation.
10. Run Supabase security and performance advisors when available.

Do not make casual destructive production changes.

## Cross-app contracts

Cross-app behavior should use explicit, opt-in platform contracts with source references rather than direct coupling or stale duplicate records.

Planned examples:

- A Daymark Scheduler work block may explicitly publish worked time to Money Earnings.
- A planned Fairway round may optionally appear in Daymark Calendar while Fairway remains the source of truth.

Sharing a Supabase project does not authorize one app to read another app's private tables.

## Roadmap

1. Money UX/visual simplification — complete; continue real-world validation.
2. Account/Profile redesign, shared identity rendering, and private avatar storage — complete; public discovery deferred.
3. Fairway UX/design and real-user-feedback pass — complete; continue real-world validation.
4. Daymark UX/design validation pass — planned.
5. Money visual/design validation pass — planned.
6. Cross-app first-user/onboarding polish — planned as needed.
7. Daymark Scheduler to Money Earnings opt-in integration — planned.
8. Money financial events to Daymark Calendar — planned.
9. Friends and safe profile discovery — planned.
10. Fairway social profiles and round invitations — planned.
11. Family/households and explicit Daymark sharing — planned.
12. Notifications — later.
13. Messaging — later and low priority.

## Updating this file

Keep this concise. It is not a changelog, commit history, bug diary, CSS log, or deployment history. Do not append every task. Update and consolidate it only when architecture, security boundaries, major capabilities, shared platform behavior, durable conventions, design principles, or roadmap status materially change.

## Implementation handoff convention

After every substantial implementation task, report a concise **Completion Update** and **Next Recommended Work**. Recommend one concrete next task with a short dependency-based reason, then list the next 2–4 roadmap items in order. Do not automatically begin that work; leave it for review and approval.
