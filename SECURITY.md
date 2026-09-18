# Security Policy

## Supported version

Security fixes target the currently deployed `main` branch. Historical commits and local forks are not maintained as supported releases.

## Reporting a vulnerability

Do not disclose authentication bypasses, cross-user access, exposed credentials, or other exploitable details in a public issue.

Use GitHub's private vulnerability-reporting flow from the repository **Security** tab when it is available. Include:

- the affected app or path;
- the minimum steps needed to reproduce the issue;
- the expected and observed authorization behavior;
- whether real user data or credentials may be at risk.

Do not include real passwords, session tokens, service-role keys, financial records, or another person's private data. Use synthetic examples wherever possible.

## Security boundaries

- Supabase Row Level Security is the authorization boundary; frontend route guards are user experience only.
- Service-role keys, database passwords, OAuth secrets, tokens, and private keys must never be committed or exposed to browser code.
- Money records are private. Daymark and Fairway data remain private unless an explicit feature shares a narrowly scoped record.
- Shared authentication, friendships, and household membership do not grant broad access to another user's app data.
- Database changes must use version-controlled migrations and include focused multi-user and anonymous-access tests.

Reports will be reviewed as availability permits. A fix may require coordinated deployment across the static frontend and Supabase migration history.
