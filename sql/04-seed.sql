-- ============================================================================
-- Two tenants with data, so the isolation test has something to try to leak.
-- ============================================================================
-- Fixed identifiers so the tests can name them. Everything here is invented and
-- the domains are reserved for examples.
--
-- Note the explicit transactions. set_tenant() is transaction-scoped on purpose,
-- and psql runs in autocommit — so a `SELECT set_tenant(...)` on its own line
-- would be its own transaction and the setting would be gone before the next
-- statement ran. A seed that appeared to work anyway would only be doing so
-- because a superuser ran it and bypassed the policies entirely.

INSERT INTO tenant (id, name, slug) VALUES
    ('aaaaaaaa-0000-4000-8000-000000000001', 'Northwind Partners', 'northwind'),
    ('aaaaaaaa-0000-4000-8000-000000000002', 'Example Holdings',   'example');

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000001');

INSERT INTO account (tenant_id, email, name) VALUES
    ('aaaaaaaa-0000-4000-8000-000000000001', 'ana@northwind.example',  'Ana'),
    ('aaaaaaaa-0000-4000-8000-000000000001', 'bruno@northwind.example','Bruno');

INSERT INTO project (id, tenant_id, name) VALUES
    ('bbbbbbbb-0000-4000-8000-000000000001',
     'aaaaaaaa-0000-4000-8000-000000000001', 'Northwind migration'),
    ('bbbbbbbb-0000-4000-8000-000000000002',
     'aaaaaaaa-0000-4000-8000-000000000001', 'Northwind audit');

INSERT INTO note (tenant_id, project_id, body) VALUES
    ('aaaaaaaa-0000-4000-8000-000000000001',
     'bbbbbbbb-0000-4000-8000-000000000001', 'Northwind: kickoff scheduled.');

COMMIT;

BEGIN;
SELECT set_tenant('aaaaaaaa-0000-4000-8000-000000000002');

INSERT INTO account (tenant_id, email, name) VALUES
    ('aaaaaaaa-0000-4000-8000-000000000002', 'clara@example.example', 'Clara');

INSERT INTO project (id, tenant_id, name) VALUES
    ('bbbbbbbb-0000-4000-8000-000000000009',
     'aaaaaaaa-0000-4000-8000-000000000002', 'Confidential to Example Holdings');

INSERT INTO note (tenant_id, project_id, body) VALUES
    ('aaaaaaaa-0000-4000-8000-000000000002',
     'bbbbbbbb-0000-4000-8000-000000000009',
     'Example Holdings: this line must never be visible to Northwind.');
COMMIT;
