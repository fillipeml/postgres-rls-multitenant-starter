-- ============================================================================
-- DEMONSTRATION: a superuser ignores row-level security entirely.
-- ============================================================================
-- Run as the superuser.
--
-- Not a flaw — it is documented and it is how a database administrator fixes
-- things. It matters here for two reasons. An application that connects as a
-- superuser has no tenant isolation at all, whatever its policies say. And an
-- isolation test run as a superuser passes while proving nothing, which is
-- worse than not running it, so test/isolation.sql refuses to run as one.

\set ON_ERROR_STOP on

DO $$
BEGIN
    IF NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'this demonstration must run as a superuser; current_user is %', current_user;
    END IF;
END;
$$;

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM project;
    IF visible <> 3 THEN
        RAISE EXCEPTION
            'demonstration did not reproduce: expected a superuser to see all 3 projects, saw %', visible;
    END IF;
    RAISE NOTICE
        'LEAK REPRODUCED: tenant A is set and FORCE is on, and the superuser sees all % projects',
        visible;
END;
$$;
COMMIT;

\echo 'leak-as-superuser: reproduced. Never connect an application as a superuser.'
