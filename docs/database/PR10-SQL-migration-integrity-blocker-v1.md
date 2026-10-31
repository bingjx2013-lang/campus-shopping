# PR #10 SQL migration integrity blocker review

Date: 2026-10-31
Branch: `work/database-review-v1`
Reviewed file: `database/migrations/0002_campus_shopping_full_schema_v1_draft.sql`
Reviewed blob: `ed9f8a1b646b787c96beb121034e8b12a911c122`
Status: BLOCKER — do not execute, merge, or deploy this SQL draft.

## Confirmed structural defects

1. The first `CREATE TABLE users(...)` statement is interrupted after the phone CHECK expression. The statement does not close before the next `CREATE TABLE student_profiles`.
2. The file later reaches a `COMMIT;`, but immediately after it contains a dangling fragment beginning `),password_hash text CHECK(...)` followed by another copy of many table definitions.
3. The duplicated tail redefines tables already created earlier, including `student_profiles`, `student_guardians`, `roles`, `permissions`, `auth_sessions`, `verification_codes`, `login_events`, `merchants`, and other entities. Even if the dangling fragment were removed, duplicate CREATE TABLE statements would fail in a fresh database.
4. The current PR #10 CI run #73 passed, but its workflow only runs dependency audit, TypeScript, ESLint, and Next.js build. It does not parse or execute this SQL, so it cannot validate migration integrity.

## Required repair sequence

- Reconstruct one canonical migration from the intended schema; do not attempt a blind text deletion because the initial users statement is split and the tail contains both missing column definitions and duplicated DDL.
- Ensure exactly one BEGIN/COMMIT pair and exactly one CREATE TABLE per table.
- Add a PostgreSQL 15 CI service or disposable database job; apply migrations from an empty database, verify expected tables/constraints/indexes, then test rollback/cleanup.
- Add a static guard that rejects content after COMMIT (except whitespace/comments) and duplicate CREATE TABLE names.
- Run auth/session constraint tests, including Argon2id format enforcement, E.164 normalization, two-minute code expiry, one-time atomic consumption, purpose isolation, rate limiting across instances, refresh-token rotation/replay revocation, and device verification.
- Only after those checks pass should the SQL draft be considered for review again.

## Safety boundary

No database was connected and no migration was executed. This finding is a static source review only. PR #10 remains a draft; do not merge or run against production.
