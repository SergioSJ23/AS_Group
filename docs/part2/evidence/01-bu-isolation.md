# Evidence: ADR-001 — Per-BU Process and Database Isolation

**QA drivers:** QA1 (Fault Isolation), QA2 (BU Pricing Autonomy)  
**Pressure points addressed:** P1 (global price), P6 (IgnoreStoreLimitations bypass), P7 (role-only ACL)  
**Test date:** 2026-05-31

---

## Claim

A failure in BU1's database or process must not affect BU2's availability or response time.
Each BU runs as an independent ASP.NET Core process backed by its own PostgreSQL database.

---

## Deployment Evidence

The full stack consists of 15 containers. Each BU has its own process and database:

```
NAME                           STATUS                        PORTS
northstar-db_bu1-1             Up (healthy)                  5432/tcp               ← BU1 private DB
northstar-db_bu2-1             Up (healthy)                  5432/tcp               ← BU2 private DB
northstar-nop_bu1-1            Up                            0.0.0.0:8081->80/tcp   ← BU1 process
northstar-nop_bu2-1            Up                            0.0.0.0:8082->80/tcp   ← BU2 process
northstar-erp_bu1-1            Up (healthy)                  0.0.0.0:9001->8080/tcp
northstar-erp_bu2-1            Up (healthy)                  0.0.0.0:9002->8080/tcp
northstar-keycloak-1           Up (healthy)                  0.0.0.0:8080->8080/tcp ← shared IdP
northstar-rabbitmq-1           Up (healthy)                  0.0.0.0:5672->5672/tcp ← shared broker
northstar-meilisearch-1        Up (healthy)                  0.0.0.0:7700->7700/tcp ← shared search
northstar-espocrm-1            Up (healthy)                  0.0.0.0:8083->80/tcp   ← shared CRM
northstar-espocrm_consumer-1   Up                            0.0.0.0:9003->9003/tcp
northstar-portal-1             Up                            0.0.0.0:8000->80/tcp
northstar-prometheus-1         Up (healthy)                  0.0.0.0:9090->9090/tcp
northstar-grafana-1            Up                            0.0.0.0:3000->3000/tcp
```

**No shared database or shared process between BU1 and BU2.** All cross-BU communication
is mediated through the shared infrastructure layer (Keycloak, RabbitMQ, Meilisearch)
reachable over the network — never through shared in-process state.

Both databases have independent schemas. The `OutboxMessage` table exists in each BU's own DB:

```
BU1 DB (nop_bu1):                     BU2 DB (nop_bu2):
  OutboxMessage (Id, BuId, Payload…)    OutboxMessage (Id, BuId, Payload…)
  Product, Order, Customer, …           Product, Order, Customer, …
  [no BU2 tables]                       [no BU1 tables]
```

---

## Fault Isolation Test

### Test procedure

1. Both storefronts confirmed healthy (HTTP 200).
2. `db_bu1` container stopped (`docker stop northstar-db_bu1-1`).
3. Both BUs polled immediately.
4. `db_bu1` restarted; recovery confirmed.

### Results

```
[17:13:51] Stopping db_bu1...
[17:13:54] BU1 DB is DOWN. Testing BU2...
[17:13:54] BU2 response:                HTTP 200  ← BU2 unaffected
[17:14:29] BU1 response (DB down):      HTTP 500  ← BU1 degraded (expected)
[17:14:29] Restarting db_bu1...
[17:14:35] BU1 after recovery:          HTTP 200  ← BU1 self-recovered
[17:14:35] BU2 unaffected throughout:   HTTP 200
```

### Interpretation

BU2 continued serving HTTP 200 throughout the entire period BU1's database was down.
BU1 degraded as expected (HTTP 500 — cannot reach its own DB). Recovery was automatic
on database restart with no manual intervention.

**QA1 satisfied by construction:** no shared failure domain at the process or database
level. A database lock, GC pause, or runaway query in BU1 cannot propagate to BU2.

---

## Pricing Autonomy (QA2)

Because each BU has its own `Product` table with its own `Price` column,
a BU1 product manager updating 200 prices writes only to `db_bu1`. BU2's pricing
queries never see `db_bu1` — there is no join, no read replica, no shared cache.
P1 (global `Product.Price` field) dissolves at the structural level: the BUs
do not share the table.

---

## What Stays in the Monolith (and Why)

| Component | Location | Reason |
|---|---|---|
| Orders, catalog, payments, shipping | Inside each nopCommerce instance | Each BU owns its commercial domain; extraction would require data migration and bidirectional sync with no benefit |
| Plugin infrastructure | Inside each nopCommerce instance | Plugins reuse existing DI, migration, and event infrastructure — no extraction needed |
| Multi-store feature | Within each BU instance | Remains useful for sub-stores within a BU; no longer load-bearing for cross-BU isolation |

---

## Known Limit

`db_bu1` stopping causes BU1 to return HTTP 500 on every request. There is no
read-only degraded mode for the nopCommerce monolith when its database is unavailable.
This is acceptable: the isolation requirement is that BU2 must not be affected, not that
BU1 must be resilient to its own database failure.
