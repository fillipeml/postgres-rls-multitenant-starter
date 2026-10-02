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
-- demo_owner reads the seeded tables in the contrast half of two demonstrations.
GRANT USAGE ON SCHEMA public TO demo_owner;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO demo_owner;
GRANT EXECUTE ON FUNCTION current_tenant() TO demo_owner;
GRANT EXECUTE ON FUNCTION set_tenant(uuid) TO demo_owner;
