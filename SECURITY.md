# Security policy

## Reporting a vulnerability

Report privately through GitHub's "Report a vulnerability" button on the Security tab. Do not
open a public issue.

Acknowledgement within 72 hours, and a fix or mitigation plan within 14 days for anything
confirmed.

## Scope

This repository exists to make one guarantee, so the guarantee is the scope: **a query must
never return another tenant's rows, and a write must never create one.**

A path that defeats that is a vulnerability here even though the data is invented. In
particular:

- A way to see or write another tenant's rows as `app_user` with the policies applied.
- A tenant setting that survives a transaction and reaches a later one on the same connection.
- A privilege `app_user` holds that it does not need.
- A mistake in one of the four demonstrations that makes it report a leak it did not reproduce,
  or miss one it did. A demonstration that lies is worse than no demonstration.

## Not in scope

The credentials in this repository. `local_dev_only` and the compose file's `postgres` password
are placeholders for a throwaway container and are meant to be visible.

The four leak demonstrations themselves. They deliberately create insecure configurations in a
scratch schema, prove the hole, and drop it. That is the point of them.

What this repository explicitly does not solve, listed in the README: resolving which tenant a
request belongs to, noisy neighbours, per-tenant encryption, and data residency. Those are real
problems and not defects here.

## Supported versions

The `main` branch. Tested against PostgreSQL 18 in CI on every push.
