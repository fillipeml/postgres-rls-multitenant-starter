-- ============================================================================
-- The application role, which is the point of FORCE.
-- ============================================================================
-- Policies protect nothing if the application connects as a superuser, because
-- a superuser bypasses row-level security entirely — see
-- test/leak-as-superuser.sql. They also protect nothing if the application
-- connects as the tables' owner and FORCE was not set.
--
-- So: tables owned by one role, used by another, and the second has exactly the
-- four privileges an application needs and no more. It cannot create a table,
-- cannot alter a policy, and cannot drop anything.
--
-- The password here is a local development placeholder and is meant to be
-- visible. A deployment passes one in rather than using this file as-is.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'local_dev_only';
    END IF;
END;
$$;

GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;

-- Applies to tables created later, so adding one does not silently leave the
-- application unable to read it until somebody remembers this file.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

-- The function is called on every request, so it has to be callable.
GRANT EXECUTE ON FUNCTION set_tenant(uuid) TO app_user;
GRANT EXECUTE ON FUNCTION current_tenant() TO app_user;
