# Bujoreanu Apps

A small ecosystem of privacy-focused web applications built as static frontends on GitHub Pages with Supabase authentication and data storage.

- **Account** — shared sign-in, profile, connections, and household management
- **Daymark** — tasks, goals, Calendar, and a daily Scheduler
- **Fairway** — golf courses, rounds, scorecards, statistics, friends, and planned rounds
- **Money** — private budgeting, transactions, earnings, savings, retirement, assets, and reports

Live site: [bujoreanu.org](https://bujoreanu.org/)

## Architecture

The browser applications are dependency-light HTML, CSS, and JavaScript deployed through GitHub Pages. Supabase provides shared authentication and a PostgreSQL database protected by Row Level Security.

Private app data is not shared merely because the apps use one account or database. Cross-app features are explicit, narrow, and source-linked.

Fairway is deployed within the same web ecosystem, but its source is maintained in a separate repository. See [the architecture overview](docs/architecture.md) for repository boundaries and security principles.

## Repository map

| Path | Purpose |
| --- | --- |
| `account/` | Shared account and profile experience |
| `tracker/` | Daymark |
| `money/` | Money |
| `shared/` | Small shared platform modules |
| `supabase/migrations/` | Version-controlled database changes |
| `supabase/tests/` | Transactional RLS and database tests |
| `docs/` | Technical documentation |

## Local development

Serve the repository root with any local static-file server. Do not open pages directly with `file://`, because routing and module behavior depend on an HTTP origin.

The frontend may contain only the browser-safe Supabase publishable/anon configuration. Never commit service-role keys, database passwords, tokens, or private keys.

## Tests

The baseline JavaScript suite uses Node's built-in test runner:

```sh
node --test tracker/scheduler.test.js tracker/fairway-events.test.js shared/profile-discovery.test.mjs money/calculations.test.js
```

Database security tests under `supabase/tests/` are intentionally transactional and require an authorized Supabase database environment. They are not run by public pull-request CI because privileged database credentials must not be exposed.

See [development and validation](docs/development.md) for the expected checks.

## Contributing and planning

Use GitHub Issues for defects and planned improvements. User-reported broken behavior is labeled `bug`; new features and improvements are labeled `enhancement`. App-area labels keep work scoped to Account, Daymark, Fairway, Money, or the shared platform.

Before changing application behavior, read `AGENTS.md` and preserve the existing security boundaries. For security concerns, follow [SECURITY.md](SECURITY.md) rather than posting sensitive details in a public issue.
