/** The one place the application talks to the database.
 *
 * THE RULE: every table has row-level security with FORCE, and the policy only
 * releases rows when `app.tenant_id` is set IN THE TRANSACTION. Two consequences
 * follow, and both are easy to get wrong in a way that produces no error.
 *
 * The setting is transaction-scoped. `set_config(..., true)` is SET LOCAL: the
 * value dies at COMMIT or ROLLBACK. That is mandatory with a connection pool —
 * a session-scoped value survives into whichever request is handed that
 * connection next, which is one tenant reading another's data with nothing in
 * any log to say so. `test/leak-without-local.sql` demonstrates it.
 *
 * The tenant arrives as a parameter, never interpolated. `SET` does not take
 * parameters, so the obvious implementation builds a string — and string
 * concatenation on the one value that decides who sees what is the worst place
 * in the system for it.
 *
 * EVERY read and write goes through this helper. Outside it the policies return
 * zero rows, which is the design: forgetting is safe, and a query that returns
 * nothing is a bug you find, not a leak you do not.
 */
import { Pool, type PoolClient } from "pg";

export interface PoolOptions {
  connectionString?: string;
  /** Low on purpose: each serverless instance holds its own pool, so the total
   *  is instances × max. A pooler in transaction mode multiplexes it, which is
   *  also why the setting above must be transaction-scoped and not session. */
  max?: number;
}

export function createPool(options: PoolOptions = {}): Pool {
  const connectionString = options.connectionString ?? process.env.DATABASE_URL;
  if (!connectionString) throw new Error("DATABASE_URL is not set");

  // node-postgres reads `sslmode=require` as "encrypt but do not verify the
  // certificate", which is an open door to a machine in the middle. Where the
  // URL asks for TLS, verification is turned on explicitly.
  const wantsTls = /[?&]sslmode=require/.test(connectionString);

  return new Pool({
    connectionString,
    ssl: wantsTls ? { rejectUnauthorized: true } : undefined,
    max: options.max ?? 5,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
  });
}

/** Runs `fn` inside one transaction, scoped to one tenant. */
export async function withTenant<T>(
  pool: Pool,
  tenantId: string,
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  if (!tenantId) throw new Error("a tenant id is required");
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

/** Runs `fn` with no tenant set. Everything under a policy returns nothing.
 *
 *  Exists so that the few queries which legitimately read the tenant root have
 *  a named way to say so, rather than reaching for the pool directly and
 *  bypassing the rule by habit.
 */
export async function withoutTenant<T>(
  pool: Pool,
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
