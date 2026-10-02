# CLAUDE.md

Working rules for AI-assisted changes in this repository. They mirror the README; the README
wins on conflict.

## Non-negotiable rules

1. **The four guarantees are proven as `app_user`, never as a superuser.** A superuser bypasses
   row-level security, so a proof run as one passes while proving nothing. `test/isolation.sql`
   has a guard that refuses, and CI asserts the guard fires.
2. **Every table except the tenant root carries `ENABLE` and `FORCE`.** CI counts them against
   `pg_class` and fails on any table that is missing either. Adding a table means adding it to
   the loop in `sql/02-rls.sql`.
3. **Every policy has both `USING` and `WITH CHECK`.** The first isolates reads, the second
   isolates writes, and a policy with only the first passes every test anyone thinks to write.
4. **The tenant setting is transaction-scoped.** `set_config(..., true)`, never a plain `SET`,
   and never built by string concatenation — it is a parameter.
5. **The leak demonstrations must keep reproducing their leaks.** Each asserts the hole exists.
   If PostgreSQL ever closes one, that script fails, and the fix is to update the README rather
   than to delete the assertion.
6. **Fictional data only.** Invented tenant names, example-reserved domains, placeholder
   passwords for throwaway containers. Nothing that could be real.

## Conventions

- PostgreSQL 18, no extensions. Node 24 with native type stripping for the client, `pg` only.
- SQL comments explain *why*, not what. This repository is read more than it is run.
- The client's public surface is `withTenant` and `withoutTenant`. Anything that reaches the
  pool directly bypasses the rule and should not exist.
- `scripts/prove.sh` is the single entry point; docker compose and CI both call it, so a step
  added to one is added to all.
- Commits: English, Conventional Commits, one logical change each, no AI attribution trailers.
