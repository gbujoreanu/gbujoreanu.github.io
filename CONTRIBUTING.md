# Contributing

This repository uses an issue-first workflow. Keep each issue and implementation task focused on one primary feature, improvement, or defect.

## Before starting work

1. Search the existing issues to avoid duplicates.
2. Use the bug form for broken or regressed behavior.
3. Use the enhancement form for a new capability or improvement.
4. Use the focused implementation form only after the work has been selected and its boundaries are understood.
5. Do not include passwords, tokens, production records, financial data, private user information, or other secrets in an issue.

## Project workflow

The linked GitHub Project is the active backlog. Its status is one of:

- **Backlog** — known work that has not been selected.
- **Ready** — explicitly selected as the next task. Keep only selected work here.
- **In Progress** — currently being implemented.
- **Testing** — implemented and awaiting final validation or deployment verification.
- **Done** — completed and closed.

Project fields identify the app, work type, priority, and approximate size. Issue labels remain intentionally small: use `bug` or `enhancement`, plus at most one app-area label (`account`, `daymark`, `fairway`, `money`, or `platform`).

## Implementation expectations

- Read `AGENTS.md` before changing code.
- Work only on the explicitly selected Ready issue.
- Preserve authentication, privacy boundaries, RLS, and existing user data.
- Keep unrelated refactors and future features out of the change.
- Add or update focused tests in proportion to risk.
- Validate the deployed user flow when the issue changes user-facing behavior.
- Never commit privileged credentials or real private datasets.

## Completion

When an issue is complete:

1. Run the relevant checks.
2. Commit and push the finished work.
3. Verify deployment when required.
4. Move the issue through Testing and close it only after validation.
5. Update the Project status; closing an issue should place it in Done.
6. Stop after that one issue unless the user explicitly selects another.

