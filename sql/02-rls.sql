-- ============================================================================
-- The whole mechanism. Four moving parts, and each one is load-bearing.
-- ============================================================================

-- 1. The tenant function.
--
-- The second argument to current_setting is `missing_ok`. With it true, an
-- unset variable returns NULL instead of raising — and NULL compares equal to
-- nothing, so a connection that forgot to set a tenant sees **zero rows**
-- rather than an error or, far worse, everything.
--
-- That is the single most important line in this repository: the default is to
-- deny, and it is the default because of how the absence of a value behaves,
-- not because of a check somebody remembered to write.
--
-- The nullif() handles the empty string, which is what set_config writes when
-- it is handed an empty parameter — without it, ''::uuid raises.
--
-- STABLE, not VOLATILE: the planner may cache it within a statement, which
-- matters when the policy is evaluated per row.

CREATE FUNCTION current_tenant() RETURNS uuid AS $$
    SELECT nullif(current_setting('app.tenant_id', true), '')::uuid;
$$ LANGUAGE sql STABLE;

-- 2. The policies, applied in a loop.
--
-- A loop rather than 29 hand-written blocks, because the one thing that must
-- never happen is a table being added to the schema and not to this list. A
-- loop over an explicit array at least puts every protected table in one place
-- where a reviewer can count them against the schema.
--
-- ENABLE turns policies on. FORCE makes them apply to the table's OWNER too —
-- without it, whichever role owns the tables bypasses every policy, and in a
-- small deployment that role is usually the application's. See
-- test/leak-without-force.sql, which demonstrates the hole.
--
-- USING filters what a statement can SEE. WITH CHECK constrains what it may
-- WRITE. Omitting WITH CHECK is not a hole — PostgreSQL falls back to the USING
-- expression for writes — but writing both is still right: the day somebody
-- widens USING for a reporting view, a policy that relies on the fallback
-- widens writes at the same time, silently.
--
-- Two things that ARE holes, each with a script that reproduces it: a table
-- added to the schema and not to this array (test/leak-forgotten-table.sql),
-- and a second PERMISSIVE policy, which combines with OR and so can only widen
-- access (test/leak-extra-permissive-policy.sql).

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['account', 'project', 'note'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format(
            'CREATE POLICY tenant_isolation_%s ON %I '
            'USING (tenant_id = current_tenant()) '
            'WITH CHECK (tenant_id = current_tenant())',
            t, t
        );
    END LOOP;
END;
$$;

-- 3. A convenience for the application, so the tenant is set the same way
--    everywhere. The `true` is the part that matters: it makes the setting
--    transaction-scoped, exactly as SET LOCAL does, so it dies at COMMIT or
--    ROLLBACK and cannot survive into whichever request reuses the pooled
--    connection next. See test/leak-without-local.sql.
--
--    Taking the value as a parameter rather than building a SET statement by
--    string concatenation is the other half: SET does not take parameters, so
--    the obvious implementation is string interpolation, which is an injection
--    point on the one value that decides who sees what.

CREATE FUNCTION set_tenant(p_tenant_id uuid) RETURNS void AS $$
    SELECT set_config('app.tenant_id', p_tenant_id::text, true);
$$ LANGUAGE sql;
