-- ============================================================================
-- The four guarantees. Run as app_user, NEVER as a superuser.
-- ============================================================================
-- If this script reaches the end, the isolation is proven. Any failure raises
-- and aborts, so a silent pass is not possible.

\set ON_ERROR_STOP on

-- Guard. A superuser bypasses row-level security entirely, so running this as
-- one proves nothing at all and would be worse than not running it: it would
-- report success. See leak-as-superuser.sql for the demonstration.
DO $$
BEGIN
    IF (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION
            'invalid test run: current_user (%) is a superuser, which bypasses RLS', current_user;
    END IF;
END;
$$;

-- 1. No tenant set: nothing is visible. The default is deny.
BEGIN;
DO $$
BEGIN
    IF (SELECT count(*) FROM account) <> 0
       OR (SELECT count(*) FROM project) <> 0
       OR (SELECT count(*) FROM note) <> 0 THEN
        RAISE EXCEPTION 'GUARANTEE 1 FAILED: a session with no tenant saw rows';
    END IF;
    RAISE NOTICE 'ok 1: with no tenant set, zero rows are visible';
END;
$$;
COMMIT;

-- 2. Tenant A sees its own rows and none of tenant B's.
BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
BEGIN
    IF (SELECT count(*) FROM project) <> 2 THEN
        RAISE EXCEPTION 'GUARANTEE 2a FAILED: expected 2 projects, saw %',
            (SELECT count(*) FROM project);
    END IF;
    IF EXISTS (SELECT 1 FROM project
               WHERE tenant_id = 'aaaaaaaa-0000-4000-8000-000000000002') THEN
        RAISE EXCEPTION 'GUARANTEE 2b FAILED: tenant A saw tenant B''s project';
    END IF;
    IF EXISTS (SELECT 1 FROM note WHERE body LIKE '%must never be visible%') THEN
        RAISE EXCEPTION 'GUARANTEE 2c FAILED: tenant A saw tenant B''s note';
    END IF;
    RAISE NOTICE 'ok 2: tenant A sees only tenant A';
END;
$$;
COMMIT;

-- 3. The mirror. Tenant B sees its own and none of A's.
BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000002');
DO $$
BEGIN
    IF (SELECT count(*) FROM project) <> 1
       OR (SELECT count(*) FROM account) <> 1 THEN
        RAISE EXCEPTION 'GUARANTEE 3a FAILED: tenant B''s view is wrong';
    END IF;
    IF EXISTS (SELECT 1 FROM account
               WHERE tenant_id = 'aaaaaaaa-0000-4000-8000-000000000001') THEN
        RAISE EXCEPTION 'GUARANTEE 3b FAILED: tenant B saw tenant A''s accounts';
    END IF;
    RAISE NOTICE 'ok 3: tenant B sees only tenant B';
END;
$$;
COMMIT;

-- 4. WITH CHECK. Acting as B, writing a row that belongs to A must be refused.
--    This is the guarantee a USING-only policy silently fails: reads would
--    still be isolated, and writes would not.
BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000002');
DO $$
BEGIN
    BEGIN
        INSERT INTO account (tenant_id, email, name)
        VALUES ('aaaaaaaa-0000-4000-8000-000000000001',
                'injected@northwind.example', 'Injected');
        RAISE EXCEPTION 'GUARANTEE 4 FAILED: a cross-tenant insert succeeded';
    EXCEPTION
        WHEN insufficient_privilege OR check_violation THEN
            RAISE NOTICE 'ok 4: the database refused the cross-tenant write (%)', SQLERRM;
    END;
END;
$$;
ROLLBACK;

\echo 'ISOLATION PROVEN: all four guarantees hold.'
