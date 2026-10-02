#!/usr/bin/env bash
# Applies everything and proves it. Used by docker compose and runnable by hand
# against any PostgreSQL: set SUPER, APP and OWNER to connection strings.
set -euo pipefail

: "${SUPER:?set SUPER to a superuser connection string}"
: "${APP:?set APP to the app_user connection string}"
: "${OWNER:?set OWNER to the demo_owner connection string}"

say() { printf '\n== %s\n' "$1"; }

say "applying schema, policies, roles and seed"
for f in /sql/01-schema.sql /sql/02-rls.sql /sql/03-roles.sql /sql/04-seed.sql; do
  psql "$SUPER" -v ON_ERROR_STOP=1 -q -f "$f"
done

say "checking every table except the tenant root carries a FORCE policy"
unprotected=$(psql "$SUPER" -v ON_ERROR_STOP=1 -t -A -c "
  SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname <> 'tenant'
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity);")
[ "$unprotected" = "0" ] || { echo "FAILED: $unprotected table(s) unprotected"; exit 1; }
echo "ok: every table is protected"

say "the four guarantees, as the unprivileged role"
psql "$APP" -v ON_ERROR_STOP=1 -f /test/isolation.sql

say "the isolation test must refuse to run as a superuser"
if psql "$SUPER" -v ON_ERROR_STOP=1 -f /test/isolation.sql >/dev/null 2>&1; then
  echo "FAILED: the guard did not fire"; exit 1
fi
echo "ok: refused"

say "setting up the leak demonstrations"
psql "$SUPER" -v ON_ERROR_STOP=1 -q -f /test/00-setup-demos.sql

say "reproducing each way to get this wrong"
psql "$OWNER" -v ON_ERROR_STOP=1 -f /test/leak-without-force.sql
psql "$APP"   -v ON_ERROR_STOP=1 -f /test/leak-without-local.sql
psql "$OWNER" -v ON_ERROR_STOP=1 -f /test/leak-without-with-check.sql
psql "$SUPER" -v ON_ERROR_STOP=1 -f /test/leak-as-superuser.sql

printf '\nAll four guarantees hold, and all four leaks reproduce.\n'
