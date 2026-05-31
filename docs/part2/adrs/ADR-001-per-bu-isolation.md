# ADR-001: Per-BU Process and Database Isolation

**Status:** Accepted  
**Drivers:** QA1 (Fault Isolation), QA2 (BU Pricing Autonomy)  
**Pressure points:** P1 (global price), P6 (IgnoreStoreLimitations bypass), P7 (role-only ACL)  
**Bounded contexts:** BC2 (BU1 Commerce), BC3 (BU2 Commerce)  
**ADD iteration:** 1

---

## Context

nopCommerce ships as a single deployable backed by one relational database. A memory leak,
slow plugin, runaway query, or background-task failure in one part of the system degrades
every other part. The platform's multi-store feature keeps catalog rows separate when
correctly configured, but does not isolate process state, the DI container, the garbage
collector, or the database connection pool. The `IgnoreStoreLimitations` toggle (P6)
sits one click away from collapsing every catalog isolation rule across the group with no
warning. Three of the seven pressure points are direct artifacts of one-instance,
one-database multi-tenancy: the global `Product.Price` field (P1), the global-bypass
toggle (P6), and the role-only-not-store ACL dimension (P7).

QA1 demands that a failure inside one BU cannot reach another. QA2 demands that one BU
can re-price 200 products without touching a setting another BU consumes. Both pressures
point at the same answer: the two BUs cannot share a process or a database.

---

## Decision

Each BU runs as its own ASP.NET Core 9 process with its own PostgreSQL database. The two
instances share no process state, no DI container, no GC, no connection pool, and no
relational database. Any failure inside one BU is structurally contained to that BU.

The shared substrate (Keycloak for identity, RabbitMQ for cross-BU events, Meilisearch
for federated search) sits outside both BUs and is reached over the network, never through
shared in-process state.

---

## Consequences

QA1's fault isolation is satisfied by construction. QA2's pricing autonomy follows
trivially: each BU has its own `Product` table with its own `Price` column. P1 dissolves
at the structural level; P6 stops being a federation-wide hazard (the toggle only affects
the one BU it lives in); P7 (role-scoped-only ACL) becomes a within-BU concern with no
group-wide leakage potential.

**Accepted cost:** Two deployments to maintain, two database lifecycles, and a
"publish to every BU" workflow that becomes an explicit multi-step admin operation rather
than a single global click.

---

## Implementation (Part 2)

- `docker-compose.yml` defines `db_bu1` and `db_bu2` as separate PostgreSQL containers with independent volumes.
- `nop_bu1` and `nop_bu2` run the same nopCommerce image but with different `ConnectionStrings__DataConnectionString` env vars pointing to their respective databases.
- No environment variable, volume, or network alias is shared between the two BU containers' application databases.

**Verification:** `scripts/test-isolation.sh` — stops `db_bu1`, polls both BUs,
confirms BU2 returns HTTP 200 while BU1 returns HTTP 500.

**Test result (2026-05-31):**
```
db_bu1 stopped → BU2: HTTP 200, BU1: HTTP 500
db_bu1 restarted → BU1: HTTP 200 (self-recovered)
```

---

## Rejected Alternatives

**Hosting both BUs as two stores inside a single nopCommerce instance** was rejected
because a single instance is a single failure domain: a memory leak or slow plugin in one
BU still degrades the other regardless of how thoroughly the catalog is scoped.

**Shared database with per-BU schemas** was rejected on the same grounds plus the
no-shared-database rule: the database becomes the new single failure domain, and silent
cross-BU collapse risk reappears one layer down.

**Per-BU containers fronting a shared database** has the same defect: the database is the
single point of failure, and schema migrations cross BU boundaries.

**Extracting a separate Price or Catalog service** was deferred: it is a major
architectural move (data migration, broken admin paths, bidirectional sync) and the
per-instance split already satisfies QA2 with no schema change.
