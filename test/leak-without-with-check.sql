-- ============================================================================
-- DEMONSTRATION: a USING-only policy isolates reads and not writes.
-- ============================================================================
-- Run as demo_owner.
--
-- USING filters what a statement can see. WITH CHECK constrains what it may
-- write. They are separate clauses, and omitting the second is easy because the
-- first is the one you test: reads look perfectly isolated.
--
-- What you get is a tenant able to insert rows belonging to another tenant —
-- and, because USING still applies, unable to see what it just wrote. The row
-- is in the other tenant's data and invisible to the one who put it there.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.read_only_policy;
CREATE TABLE demo.read_only_policy (tenant_id uuid NOT NULL, body text NOT NULL);
ALTER TABLE demo.read_only_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.read_only_policy FORCE ROW LEVEL SECURITY;

-- The missing clause is: WITH CHECK (tenant_id = current_tenant())
CREATE POLICY isolation ON demo.read_only_policy
    USING (tenant_id = current_tenant());

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000002');
DO $$
DECLARE visible int;
BEGIN
    INSERT INTO demo.read_only_policy
        VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'written by tenant B into tenant A');
    SELECT count(*) INTO visible FROM demo.read_only_policy;
    RAISE NOTICE
        'LEAK REPRODUCED: tenant B wrote a row belonging to tenant A, and now sees % of them',
        visible;
EXCEPTION
    WHEN insufficient_privilege OR check_violation THEN
        RAISE EXCEPTION
            'demonstration did not reproduce: the write was refused without a WITH CHECK clause';
END;
$$;
COMMIT;

-- Add the missing clause and try again.
DROP POLICY isolation ON demo.read_only_policy;
CREATE POLICY isolation ON demo.read_only_policy
    USING (tenant_id = current_tenant()) WITH CHECK (tenant_id = current_tenant());

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000002');
DO $$
BEGIN
    BEGIN
        INSERT INTO demo.read_only_policy
            VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'second attempt');
        RAISE EXCEPTION 'WITH CHECK present and the cross-tenant write still succeeded';
    EXCEPTION
        WHEN insufficient_privilege OR check_violation THEN
            RAISE NOTICE 'ok: with WITH CHECK, the same write is refused (%)', SQLERRM;
    END;
END;
$$;
ROLLBACK;

DROP TABLE demo.read_only_policy;
\echo 'leak-without-with-check: reproduced, and closed by the WITH CHECK clause.'
