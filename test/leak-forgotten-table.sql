-- ============================================================================
-- DEMONSTRATION: a table added to the schema and not to the policy list.
-- ============================================================================
-- Run as demo_owner.
--
-- This is the one that actually happens. The policies are right, the proof
-- passes, and six months later somebody adds a table in a migration and does
-- not add it to the loop in sql/02-rls.sql. Row-level security is off for that
-- table, so there is no policy to fail — every tenant sees every row in it, and
-- nothing anywhere reports a problem.
--
-- It is the reason the policy list is a loop over an explicit array rather than
-- a hand-written block per table, and the reason CI counts the protected tables
-- against pg_class on every push instead of trusting that anyone looked.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.forgotten;
CREATE TABLE demo.forgotten (tenant_id uuid NOT NULL, body text NOT NULL);

INSERT INTO demo.forgotten VALUES
    ('aaaaaaaa-0000-4000-8000-000000000001', 'belongs to tenant A'),
    ('aaaaaaaa-0000-4000-8000-000000000002', 'belongs to tenant B');

-- The missing lines are the three in sql/02-rls.sql: ENABLE, FORCE, CREATE POLICY.

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.forgotten;
    IF visible <> 2 THEN
        RAISE EXCEPTION
            'demonstration did not reproduce: a table with no policy should show both rows, showed %',
            visible;
    END IF;
    RAISE NOTICE
        'LEAK REPRODUCED: tenant A is set and this table has no policy, so all % rows are visible',
        visible;
END;
$$;
COMMIT;

-- What the CI check looks for. Any table outside this list is the bug above.
DO $$
DECLARE unprotected int;
BEGIN
    SELECT count(*) INTO unprotected
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'demo' AND c.relkind = 'r'
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity);
    IF unprotected < 1 THEN
        RAISE EXCEPTION 'the detector failed to notice an unprotected table';
    END IF;
    RAISE NOTICE 'ok: a catalogue query finds the unprotected table (% of them)', unprotected;
END;
$$;

-- Close it the way the schema does.
ALTER TABLE demo.forgotten ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.forgotten FORCE ROW LEVEL SECURITY;
CREATE POLICY isolation ON demo.forgotten
    USING (tenant_id = current_tenant()) WITH CHECK (tenant_id = current_tenant());

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.forgotten;
    IF visible <> 1 THEN
        RAISE EXCEPTION 'with the policy applied the owner should see 1 row, saw %', visible;
    END IF;
    RAISE NOTICE 'ok: with the three missing lines, the same query sees % row', visible;
END;
$$;
COMMIT;

DROP TABLE demo.forgotten;
\echo 'leak-forgotten-table: reproduced, and caught by a catalogue query.'
