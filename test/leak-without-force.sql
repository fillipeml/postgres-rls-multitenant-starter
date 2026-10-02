-- ============================================================================
-- DEMONSTRATION: ENABLE without FORCE, and the owner walks straight through.
-- ============================================================================
-- Run as demo_owner (a non-superuser that owns the table).
--
-- ENABLE ROW LEVEL SECURITY turns the policies on for everyone EXCEPT the
-- table's owner. In a small deployment the owner is very often the role the
-- application connects with — the migrations and the app share one connection
-- string — and in that arrangement every policy in the database is decoration.
--
-- This script asserts the hole exists. If a future PostgreSQL closes it, this
-- fails and the README is wrong.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.unforced;
CREATE TABLE demo.unforced (tenant_id uuid NOT NULL, body text NOT NULL);

INSERT INTO demo.unforced VALUES
    ('aaaaaaaa-0000-4000-8000-000000000001', 'belongs to tenant A'),
    ('aaaaaaaa-0000-4000-8000-000000000002', 'belongs to tenant B');

ALTER TABLE demo.unforced ENABLE ROW LEVEL SECURITY;
-- The missing line is: ALTER TABLE demo.unforced FORCE ROW LEVEL SECURITY;
CREATE POLICY isolation ON demo.unforced
    USING (tenant_id = current_tenant()) WITH CHECK (tenant_id = current_tenant());

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.unforced;
    IF visible <> 2 THEN
        RAISE EXCEPTION
            'demonstration did not reproduce: expected the owner to see both rows, saw %', visible;
    END IF;
    RAISE NOTICE 'LEAK REPRODUCED: tenant A is set, a policy exists, and the owner still sees % rows', visible;
END;
$$;
COMMIT;

-- The same table WITH force, for contrast.
ALTER TABLE demo.unforced FORCE ROW LEVEL SECURITY;

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.unforced;
    IF visible <> 1 THEN
        RAISE EXCEPTION 'with FORCE the owner should see 1 row, saw %', visible;
    END IF;
    RAISE NOTICE 'ok: with FORCE, the same owner sees % row', visible;
END;
$$;
COMMIT;

DROP TABLE demo.unforced;
\echo 'leak-without-force: reproduced, and closed by FORCE.'
