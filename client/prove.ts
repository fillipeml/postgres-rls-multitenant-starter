/** Proves the client half of the rule, through a real pool.
 *
 * The SQL tests prove the policies. This proves the thing the policies cannot:
 * that the application's helper scopes the tenant to the transaction, so a
 * pooled connection handed to the next request carries nothing with it.
 *
 * The pool is deliberately capped at ONE connection, so every query below is
 * guaranteed to reuse the same physical connection. That is the condition under
 * which a session-scoped setting leaks, and testing it with a larger pool would
 * pass by luck.
 */
import { createPool, withTenant, withoutTenant } from "./db.ts";

const TENANT_A = "aaaaaaaa-0000-4000-8000-000000000001";
const TENANT_B = "aaaaaaaa-0000-4000-8000-000000000002";

function check(condition: boolean, message: string): void {
  if (!condition) {
    console.error(`FAILED: ${message}`);
    process.exitCode = 1;
    return;
  }
  console.log(`ok: ${message}`);
}

const pool = createPool({ max: 1 });

try {
  const a = await withTenant(pool, TENANT_A, async (client) =>
    Number((await client.query("SELECT count(*) FROM project")).rows[0].count),
  );
  check(a === 2, `tenant A sees its 2 projects (saw ${a})`);

  const b = await withTenant(pool, TENANT_B, async (client) =>
    Number((await client.query("SELECT count(*) FROM project")).rows[0].count),
  );
  check(b === 1, `tenant B sees its 1 project (saw ${b})`);

  // The one that matters: the same physical connection, no tenant set.
  const leaked = await withoutTenant(pool, async (client) =>
    Number((await client.query("SELECT count(*) FROM project")).rows[0].count),
  );
  check(leaked === 0, `the reused connection carries no tenant and sees ${leaked} rows`);

  const crossTenant = await withTenant(pool, TENANT_B, async (client) => {
    try {
      await client.query(
        "INSERT INTO account (tenant_id, email, name) VALUES ($1, $2, $3)",
        [TENANT_A, "injected@northwind.example", "Injected"],
      );
      return "accepted";
    } catch (error) {
      // Only a policy refusal counts. Catching everything would have reported success for a
      // typo in the table name or a dropped connection — a proof that passes when the thing
      // it proves is absent. These are the two SQLSTATEs test/isolation.sql accepts:
      // 42501 insufficient_privilege, raised by a WITH CHECK refusal, and 23514
      // check_violation.
      const code = (error as { code?: string }).code;
      if (code !== "42501" && code !== "23514") throw error;
      return "refused";
    }
  });
  check(crossTenant === "refused", "a cross-tenant write is refused by the database");

  // A failure inside the transaction must not leave the tenant behind either.
  await withTenant(pool, TENANT_A, async () => {
    throw new Error("deliberate failure");
  }).catch(() => undefined);
  const afterRollback = await withoutTenant(pool, async (client) =>
    Number((await client.query("SELECT count(*) FROM project")).rows[0].count),
  );
  check(afterRollback === 0, `after a rollback the connection is clean (saw ${afterRollback} rows)`);
} finally {
  await pool.end();
}

if (process.exitCode) {
  console.error("\nthe client does not uphold the rule");
} else {
  console.log("\nthe client upholds the rule: tenant scope dies with the transaction");
}
