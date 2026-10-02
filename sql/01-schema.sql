-- ============================================================================
-- A small multi-tenant domain, so the policies below have something to protect.
-- ============================================================================
-- Three tables and a tenant root. The domain is deliberately boring: what this
-- repository is about is the four lines in 02-rls.sql and the one helper in
-- client/, not the schema.
--
-- The rule every table follows: a tenant column, NOT NULL, with a foreign key
-- to the tenant root. A nullable tenant column is a row that belongs to nobody
-- and is therefore invisible to everyone, which is a bug that takes a long time
-- to find.
-- ============================================================================

CREATE TABLE tenant (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    slug       text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- The tenant root is the ONE table that does not get a policy: it is the list
-- of tenants, so a policy on it would need a tenant to read it.

CREATE TABLE account (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  uuid NOT NULL REFERENCES tenant(id),
    email      text NOT NULL,
    name       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, email)
);

CREATE TABLE project (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  uuid NOT NULL REFERENCES tenant(id),
    name       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name),
    -- Needed before `note` can reference (tenant_id, id) as a composite key.
    UNIQUE (tenant_id, id)
);

CREATE TABLE note (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  uuid NOT NULL REFERENCES tenant(id),
    project_id uuid NOT NULL REFERENCES project(id),
    body       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    -- A composite foreign key, so a note cannot point at another tenant's
    -- project even before the policies are considered. Belt and braces: the
    -- policy would catch it on read, and this catches it on write.
    FOREIGN KEY (tenant_id, project_id) REFERENCES project (tenant_id, id)
);
