# Architecture overview

## Hosting and services

- GitHub Pages serves static HTML, CSS, JavaScript, and assets.
- Supabase supplies shared authentication, PostgreSQL storage, private avatar storage, and Row Level Security.
- The public frontend uses only browser-safe Supabase configuration.

No long-running application server is required by the current architecture.

## Application boundaries

Account, Daymark, Fairway, and Money share authentication and a deliberately small platform layer. Each app retains its own navigation, visual identity, settings, business logic, and private data authorization.

The portfolio, Account, Daymark, Money, shared modules, and Supabase migrations live in this repository. Fairway source is maintained separately even though it is deployed under the same public origin.

## Shared platform

`shared/` contains only infrastructure that genuinely belongs to the ecosystem, such as session handling, app metadata, profile/avatar rendering, relationship helpers, and household access helpers. App-specific screens and rules stay inside the owning app.

Cross-app records use explicit source references rather than disconnected copies. The source app remains authoritative, and access is revalidated when source-linked data is read.

## Database changes

All schema changes belong in `supabase/migrations/`. Security and isolation checks belong in `supabase/tests/`. Migrations must preserve legitimate data and review constraints, grants, indexes, RLS policies, triggers, and privileged functions.
