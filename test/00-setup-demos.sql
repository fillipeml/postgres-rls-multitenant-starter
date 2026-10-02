-- ============================================================================
-- Setup for the leak demonstrations. Run once, as the owner/superuser.
-- ============================================================================
-- The demonstrations need a NON-superuser role that owns its own tables, so the
-- "owner bypasses the policy" case can be shown without a superuser confounding
-- it: a superuser bypasses row-level security whatever the policy says, which
-- is its own demonstration and a different one.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'demo_owner') THEN
        CREATE ROLE demo_owner LOGIN PASSWORD 'local_dev_only';
    END IF;
END;
$$;

CREATE SCHEMA IF NOT EXISTS demo AUTHORIZATION demo_owner;
GRANT USAGE ON SCHEMA demo TO app_user;
-- demo_owner needs the schema itself because the demonstrations call current_tenant()
-- and set_tenant() unqualified. It is given no rights over the seeded tables: the only
-- demonstration that read them was the WITH CHECK one, removed when its premise proved wrong.
GRANT USAGE ON SCHEMA public TO demo_owner;
GRANT EXECUTE ON FUNCTION current_tenant() TO demo_owner;
GRANT EXECUTE ON FUNCTION set_tenant(uuid) TO demo_owner;
