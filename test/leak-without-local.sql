-- ============================================================================
-- DEMONSTRATION: a session-scoped tenant survives the transaction, and with a
-- connection pool that means it survives into somebody else's request.
-- ============================================================================
-- Run as app_user.
--
-- set_config's third argument is `is_local`. With true, the value dies at
-- COMMIT or ROLLBACK, exactly like SET LOCAL. With false — which is what a
-- plain `SET app.tenant_id = ...` does — it lives for the rest of the session.
--
-- A session is a connection. With a pool, that connection goes back to the pool
-- and is handed to the next request, which may belong to a different tenant and
-- which will not set the value if its code path happens not to. There is no
-- error, no warning, and the symptom is one customer seeing another's data.
--
-- This script asserts the leak. One psql session is one connection, so the
-- second transaction below stands in for the next request to be handed it.

\set ON_ERROR_STOP on

-- The wrong way: is_local = false.
BEGIN;
SELECT set_config('app.tenant_id', 'aaaaaaaa-0000-4000-8000-000000000001', false);
COMMIT;

-- A new transaction on the same connection. Nothing here sets a tenant.
BEGIN;
DO $$
DECLARE leaked uuid; visible int;
BEGIN
    SELECT current_tenant() INTO leaked;
    SELECT count(*) INTO visible FROM project;
    IF leaked IS NULL THEN
        RAISE EXCEPTION
            'demonstration did not reproduce: the session setting did not survive the commit';
    END IF;
    RAISE NOTICE
        'LEAK REPRODUCED: a transaction that set no tenant inherited % and sees % project(s)',
        leaked, visible;
END;
$$;
COMMIT;

RESET app.tenant_id;

-- The right way: is_local = true, which is what set_tenant() uses.
BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
COMMIT;

BEGIN;
DO $$
DECLARE leaked uuid; visible int;
BEGIN
    SELECT current_tenant() INTO leaked;
    SELECT count(*) INTO visible FROM project;
    IF leaked IS NOT NULL THEN
        RAISE EXCEPTION 'transaction-scoped setting leaked: %', leaked;
    END IF;
    IF visible <> 0 THEN
        RAISE EXCEPTION 'expected zero rows with no tenant, saw %', visible;
    END IF;
    RAISE NOTICE 'ok: the transaction-scoped setting is gone, and % rows are visible', visible;
END;
$$;
COMMIT;

\echo 'leak-without-local: reproduced, and closed by the is_local flag.'
