# postgres-rls-multitenant-starter

Multi-tenant isolation enforced by PostgreSQL rather than by your application code: the four
guarantees **proven** as an unprivileged role, and the ways to get it wrong **reproduced**
so the holes are visible rather than described.

![CI](https://github.com/fillipeml/postgres-rls-multitenant-starter/actions/workflows/ci.yml/badge.svg) ![Licence: MIT](https://img.shields.io/badge/licence-MIT-informational)

```
$ docker compose up --abort-on-container-exit

== the four guarantees, as the unprivileged role
NOTICE:  ok 1: with no tenant set, zero rows are visible
NOTICE:  ok 2: tenant A sees only tenant A
NOTICE:  ok 3: tenant B sees only tenant B
NOTICE:  ok 4: the database refused the cross-tenant write
ISOLATION PROVEN: all four guarantees hold.

== reproducing each way to get this wrong
NOTICE:  LEAK REPRODUCED: tenant A is set, a policy exists, and the owner still sees 2 rows
NOTICE:  LEAK REPRODUCED: a transaction that set no tenant inherited aaaaaaaa-… and sees 2 project(s)
NOTICE:  LEAK REPRODUCED: tenant A is set and this table has no policy, so all 2 rows are visible
NOTICE:  LEAK REPRODUCED: a second permissive policy was ADDED and tenant A now sees all 2 rows
NOTICE:  LEAK REPRODUCED: tenant A is set and FORCE is on, and the superuser sees all 3 projects

All four guarantees hold, and every leak reproduces.
```

## The problem

Every multi-tenant application has a rule: a query must never return another tenant's rows. The
usual place to enforce it is the application — a `WHERE tenant_id = ?` on every query, or an
ORM scope, or a repository base class.

That works until the one query that forgets. There is no error when it does. The symptom is a
customer seeing another customer's data, and the gap between the mistake and the discovery is
usually measured in months.

Moving the rule into the database changes the failure mode. A forgotten tenant returns **zero
rows** instead of everything — a bug you find in development rather than a leak you do not find
at all.

## What it does

- A policy on every table, created in a loop so adding a table and forgetting the policy is one
  visible omission rather than a silent one.
- A tenant function whose *absence* of a value denies, so the safe behaviour is the default.
- Transaction-scoped tenant context, which is what makes this safe behind a connection pool.
- An unprivileged application role, separate from the role that owns the tables.
- A four-guarantee proof that refuses to run as a superuser, because a superuser bypasses
  row-level security and would pass while proving nothing.
- Four demonstrations that each reproduce a specific hole, and then close it — plus a
  written record of a fifth claim that turned out to be wrong, and of the CI run that
  disproved it before anybody read it.
- A client helper for Node showing the application half of the rule, proven through a pool
  capped at one connection.

## How it works

Four moving parts, each load-bearing.

**The tenant function denies by default.**

```sql
CREATE FUNCTION current_tenant() RETURNS uuid AS $$
    SELECT nullif(current_setting('app.tenant_id', true), '')::uuid;
$$ LANGUAGE sql STABLE;
```

The `true` is `missing_ok`. An unset variable returns NULL rather than raising, and NULL equals
nothing — so a connection that forgot to set a tenant sees zero rows. That property is the whole
design: safety comes from how an absent value behaves, not from a check somebody remembered.

**The policies are applied in a loop.**

```sql
FOREACH t IN ARRAY ARRAY['account', 'project', 'note'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format(
        'CREATE POLICY tenant_isolation_%s ON %I '
        'USING (tenant_id = current_tenant()) '
        'WITH CHECK (tenant_id = current_tenant())', t, t);
END LOOP;
```

`ENABLE` turns policies on for everyone except the table's owner. `FORCE` includes the owner —
and in a small deployment the owner is usually the role the application connects with, because
migrations and the app share one connection string. `USING` filters reads and `WITH CHECK`
constrains writes; both are written out rather than relying on the fallback, for the reason
below.

A loop, rather than a block per table, because the failure that actually happens is a table
added to the schema and not to the list. One array in one file is something a reviewer can count
against the schema, and CI counts it for them.

**The context is scoped to the transaction.**

```sql
SELECT set_config('app.tenant_id', $1, true);
```

The third argument makes it `SET LOCAL`: the value dies at COMMIT or ROLLBACK. Without it the
setting lives for the session — and a session is a connection, which goes back to the pool and
is handed to the next request. The tenant is also passed as a parameter rather than
interpolated, because `SET` takes no parameters and the obvious workaround is string
concatenation on the one value that decides who sees what.

**The application connects as nobody important.** Tables owned by one role, used by another with
exactly four privileges and no more. It cannot create a table, alter a policy, or drop anything.

## The holes, reproduced

Each of these is a script that asserts the leak happens, so if a future PostgreSQL closes one,
CI fails and this document is wrong rather than quietly stale.

| Script | What it shows |
| --- | --- |
| [`leak-without-force.sql`](test/leak-without-force.sql) | `ENABLE` without `FORCE`: a policy exists, a tenant is set, and the table's **owner** still sees every row |
| [`leak-without-local.sql`](test/leak-without-local.sql) | A session-scoped setting survives the commit, so the next transaction on that connection **inherits a tenant it never set** |
| [`leak-forgotten-table.sql`](test/leak-forgotten-table.sql) | A table added to the schema and **not to the policy list**: no policy means nothing to fail, so every tenant sees every row |
| [`leak-extra-permissive-policy.sql`](test/leak-extra-permissive-policy.sql) | Permissive policies combine with **OR**, so a second one *added* for a reporting view can only widen access — and reads, in review, like tightening |
| [`leak-as-superuser.sql`](test/leak-as-superuser.sql) | A superuser ignores row-level security entirely, which is why the proof refuses to run as one |

The forgotten table is the one that actually happens. The policies are right, the proof passes,
and six months later a migration adds a table and not its policy. That is why the list is a loop
over an explicit array and why CI counts the protected tables against `pg_class` on every push,
rather than trusting that somebody looked.

**One hole that is not a hole, and cost me a CI run to find out.** A policy with `USING` and no
`WITH CHECK` looks like it would isolate reads and leave writes open. It does not: PostgreSQL
falls back to the `USING` expression for writes. The demonstration asserting otherwise failed,
which is exactly what an assertion is for — a documented claim that stops being true should
break the build rather than quietly mislead. Writing both clauses is still right, because the
day somebody widens `USING` for a reporting view, a policy relying on the fallback widens writes
at the same moment and says nothing.

## Running it

```bash
docker compose up --abort-on-container-exit     # everything, from nothing
```

Or against a PostgreSQL you already have:

```bash
export SUPER='postgres://postgres:...@localhost:5432/rls_demo'
export APP='postgres://app_user:local_dev_only@localhost:5432/rls_demo'
export OWNER='postgres://demo_owner:local_dev_only@localhost:5432/rls_demo'
./scripts/prove.sh
```

And the client half, which the SQL cannot prove:

```bash
npm ci
DATABASE_URL="$APP" npm run prove
```

That one runs through a pool **capped at a single connection**, so every query is guaranteed to
reuse the same physical connection. That is the condition under which a session-scoped setting
leaks; a larger pool would pass by luck.

## Using it in an application

```typescript
import { createPool, withTenant } from "./client/db.ts";

const pool = createPool();

const projects = await withTenant(pool, session.tenantId, async (client) =>
  (await client.query("SELECT id, name FROM project ORDER BY name")).rows,
);
```

No `WHERE tenant_id = ?`. The query says what it wants and the database decides what it is
allowed to have. The rule for the rest of the codebase is one sentence: **every read and every
write goes through this helper**, because outside it the policies return nothing.

That is the property worth having. A developer who forgets gets an empty result in development,
not a leak in production.

## What this does not solve

**Resolving the tenant from the request.** This repository takes a tenant id and scopes a
transaction to it. Deciding *which* tenant a request belongs to — from a session, a subdomain, a
token claim — is the application's job, and it is the step where the actual authorisation bug
usually lives. Getting the database half right does not make the other half safe.

**Noisy neighbours.** Shared tables mean shared indexes, shared cache and shared autovacuum. One
tenant's traffic affects another's latency, and no policy changes that.

**Per-tenant encryption or data residency.** If a tenant must have its data in a different
jurisdiction or under its own key, row-level security in a shared table is the wrong shape and a
database per tenant is the right one.

**Performance at scale.** The policy is a predicate evaluated per row, so a composite index
leading with the tenant column is usually what you want, and `EXPLAIN` on a hot query is worth
doing before assuming this is free.

## Where it comes from

Extracted from a production customer-relationship system for a law firm, where the same
mechanism protects 29 tables and the isolation was proven the same way before the first pilot
user logged in. The write-up of that system is in
[portfolio](https://github.com/fillipeml/portfolio/blob/main/case-studies/law-firm-crm.md);
this is the part of it that is generic, with the domain replaced by three invented tables.

## How AI was used

No model is involved at runtime. There is no model in this repository at all.

An AI coding assistant was used to build it, and the thing worth recording is a claim it got
wrong. The repository originally carried a fifth demonstration asserting that a policy with
`USING` and no `WITH CHECK` leaves writes unprotected. That is false: PostgreSQL falls back to
the `USING` expression for writes when `WITH CHECK` is absent, so the "leak" could not be
reproduced. The assertion failed in CI before anyone read the README, which is the only reason
the claim never shipped — and the reason every demonstration here asserts that its hole exists
rather than describing it in a comment. A demonstration that merely narrates cannot be wrong
out loud.

Two smaller ones, both caught by measuring rather than by reading. `createPool` set
`ssl: { rejectUnauthorized: true }` next to an `sslmode=require` URL; printing
`client.connectionParameters.ssl` showed `{}`, because node-postgres resolves TLS from the
connection string and discards what was passed beside it — a guard that could not fire, next to
a comment that described the opposite of what pg 8 actually does. And the cross-tenant write
check caught every error rather than a policy refusal, so it would have reported success for a
typo in the table name.

**Validated:** CI applies the schema against a real PostgreSQL 18, counts unprotected tables
against `pg_class`, runs the four guarantees as the unprivileged role, asserts the superuser
guard fires, and reproduces all five holes. It does that by running `scripts/prove.sh`, the
same entry point `docker compose up` uses, so the two cannot drift.

## Data and privacy

Nothing here is real and nothing here is private.

Every tenant, person, e-mail address and invoice in `sql/04-seed.sql` is invented, and every
e-mail domain is under the `.example` TLD reserved by RFC 2606 for exactly this. There is no
production data of any kind, and no data of any kind that came from anywhere else.

The credentials are deliberately visible: `local_dev_only` and the compose file's `postgres`
password belong to a throwaway container that exists for the length of one `docker compose up`.
They are placeholders, not secrets, and `SECURITY.md` says so.

## Built with

PostgreSQL 18 and nothing else on the database side — no extension, no sidecar, no proxy. The
client helper is Node 24 with native type stripping and `pg`. The mechanism — `sql/`, `client/`,
`test/` and `scripts/` — is about 900 lines, roughly a third of them comments explaining why.

## Licence

MIT — see [LICENSE](LICENSE).
