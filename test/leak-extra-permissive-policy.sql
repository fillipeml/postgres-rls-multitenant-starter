-- ============================================================================
-- DEMONSTRATION: policies are OR'd, so adding one always widens access.
-- ============================================================================
-- Run as demo_owner.
--
-- Multiple PERMISSIVE policies on a table combine with OR. That is the default
-- kind, and it is the one every example uses. So a second policy added later for
-- some reasonable-sounding reason — an admin screen, a reporting job, a support
-- tool — does not narrow anything and cannot: it can only let more through.
--
-- The reviewer of that change sees a new policy being added, which reads as
-- tightening. It is the opposite.
--
-- The counterpart is RESTRICTIVE, which combines with AND. If a second condition
-- genuinely has to hold, that is the keyword, and it is easy to go years without
-- meeting it.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.two_policies;
CREATE TABLE demo.two_policies (tenant_id uuid NOT NULL, body text NOT NULL);

INSERT INTO demo.two_policies VALUES
    ('aaaaaaaa-0000-4000-8000-000000000001', 'belongs to tenant A'),
    ('aaaaaaaa-0000-4000-8000-000000000002', 'belongs to tenant B');

ALTER TABLE demo.two_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.two_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY isolation ON demo.two_policies
    USING (tenant_id = current_tenant()) WITH CHECK (tenant_id = current_tenant());

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.two_policies;
    IF visible <> 1 THEN
        RAISE EXCEPTION 'expected correct isolation to start with, saw % rows', visible;
    END IF;
    RAISE NOTICE 'ok: with one policy, tenant A sees % row', visible;
END;
$$;
COMMIT;

-- Somebody adds a reporting policy. It looks local and harmless.
CREATE POLICY reporting ON demo.two_policies FOR SELECT USING (true);

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.two_policies;
    IF visible <> 2 THEN
        RAISE EXCEPTION
            'demonstration did not reproduce: a second permissive policy should have widened access, saw % rows',
            visible;
    END IF;
    RAISE NOTICE
        'LEAK REPRODUCED: a second permissive policy was ADDED and tenant A now sees all % rows',
        visible;
END;
$$;
COMMIT;

-- RESTRICTIVE combines with AND, which is what "add a condition" has to mean.
DROP POLICY reporting ON demo.two_policies;
CREATE POLICY reporting ON demo.two_policies AS RESTRICTIVE FOR SELECT USING (true);

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE visible int;
BEGIN
    SELECT count(*) INTO visible FROM demo.two_policies;
    IF visible <> 1 THEN
        RAISE EXCEPTION 'a restrictive policy should not widen access, saw % rows', visible;
    END IF;
    RAISE NOTICE 'ok: as RESTRICTIVE, the same second policy leaves tenant A seeing % row', visible;
END;
$$;
COMMIT;

DROP TABLE demo.two_policies;
\echo 'leak-extra-permissive-policy: reproduced, and closed by RESTRICTIVE.'
