# Known Limitations and Honest Scope Boundaries

This document records the design decisions that were deferred, the bounds that were not
tightened, and the failure modes that the architecture discloses rather than hides.
Honest limitation tracking is part of the architecture — silent failures are worse than
visible ones.

---

## Structural Limitations

### L1 — Keycloak is a group-level authentication SPOF

**What it means:** When Keycloak is unavailable, no new logins are possible on either BU.
Users already logged in continue working (cookie-backed sessions last until token expiry,
typically 5–30 minutes). After that, they cannot re-authenticate until Keycloak recovers.

**Mitigation in place:** Short-lived access tokens with sliding refresh windows. Production
deployment uses a Keycloak HA pair (primary + standby). Cookie-backed sessions allow
already-logged-in users to continue uninterrupted.

**What is NOT mitigated:** A simultaneous failure of both HA Keycloak nodes would block
new logins for both BUs until recovery. There is no offline authentication fallback.

**Trace:** ADR-002, Risk R1

---

### L2 — Pending-fulfilment orders after ERP recovery are not automatically reconciled

**What it means:** When BU2's ERP circuit breaker opens, confirmed orders during that
window enter a `pending-fulfilment` state (checkout discloses "stock to be confirmed at
fulfilment"). After ERP recovery, the architecture does not automatically reconcile
whether those orders can actually be fulfilled.

**Mitigation in place:** Orders in `pending-fulfilment` state are visible in the BU admin
panel. The circuit breaker closes automatically; ERP reads resume normal stock accuracy.

**What is NOT mitigated:** The reconciliation workflow (notify customer, offer refund or
backorder) is a manual operational step. The architecture records the state; the resolution
is outside current scope.

**Trace:** ADR-004, Risk R8

---

### L3 — DB fallback search returns BU-scoped results only

**What it means:** When Meilisearch is unavailable, each BU falls back to its own
PostgreSQL full-text search. A customer searching on BU1 during an outage will not see
BU2 products. The "shared customer experience across federated units" use case degrades
to BU-local-only during outages.

**Mitigation in place:** Banner disclosed to the customer. Automatic recovery when
Meilisearch comes back.

**What is NOT mitigated:** No cached cross-BU results to serve during outage. The
fallback is BU-local by design (the DB cannot cross BU boundaries without violating
ADR-001).

**Trace:** ADR-005, QA4

---

### L4 — Two independently maintained BU deployments create operational drift risk

**What it means:** With two nopCommerce instances to maintain, BU teams can diverge on
nopCommerce version, plugin roster, or security patch cadence. A single instance update
that breaks BU1 may or may not be visible to BU2 until it updates too.

**Mitigation in place:** Shared `docker-compose.yml` uses the same base image for both
BUs. Shared CI pipeline (`dotnet.yml`) builds both BUs from the same codebase. Quarterly
version-sync calendar and an integration test that asserts both BUs run the same
nopCommerce version (unless an exception is recorded).

**What is NOT mitigated:** Divergence in per-BU plugin configuration (different plugins
installed or differently configured per BU) is not enforced by the architecture. It
requires operational discipline.

**Trace:** ADR-001, Risk R3

---

## Consistency Bounds

### C1 — Order events reach EspoCRM with eventual consistency (not strong)

**Bound:** Under normal conditions, an order placed in any BU reaches EspoCRM within
30 seconds. During a CRM consumer outage, messages accumulate in RabbitMQ durably and are
processed in order on recovery — but the CRM profile will be stale for the duration of
the outage.

**Disclosed to:** CRM users (e.g., support team accessing EspoCRM during an outage will
see stale cross-BU order history). No disclosure to end customers (the outbox write is
invisible to them).

---

### C2 — Meilisearch index can drift during extended outages

**Bound:** Index drift is bounded by the RabbitMQ retention window (default 7 days). Any
product changes published to RabbitMQ during a Meilisearch outage will be re-indexed on
recovery by draining the event backlog.

**Disclosed to:** Customers via the "results may be limited" banner during fallback.

---

### C3 — Cached ERP stock is stale for up to 5 minutes

**Bound:** When the circuit breaker is open, the stock figure served to customers comes
from a cache with a 5-minute TTL. A product that sold out in the last 5 minutes may still
show as available.

**Disclosed to:** Customers via "stock to be confirmed at fulfilment" banner. Oversold
orders enter `pending-fulfilment` state (see L2).

---

## Scope Cuts Taken Deliberately

### S1 — No automated ERP reconciliation workflow

The `pending-fulfilment` state is recorded; the reconciliation policy (refund, backorder,
manual fulfil) is not implemented. This is an honest scope cut: the architectural
requirement is that the system records the state and remains available; the operational
resolution is a product/business decision outside the architecture brief.

### S2 — Keycloak HA pair not fully wired in the demo environment

The `docker-compose.yml` runs a single Keycloak instance. The HA configuration (primary +
standby with shared DB) is documented in ADR-002 and the risk register but not deployed
in the demo environment. Deploying HA Keycloak in docker-compose adds complexity that
obscures the demo's primary value.

### S3 — Load test results not captured in this evidence pack

The three k6 load scenarios (`search-load`, `checkout-load`, `product-detail-load`)
exist and run correctly. The results flow into Grafana via Prometheus. Screenshots of
the Grafana dashboard during a load run are available from the demo environment but
were not captured as static files in this evidence pack. The Grafana dashboard
(`observability/grafana/dashboards/adr-evidence.json`) with 19 panels covers all ADRs.

### S4 — Only 8 products in the demo dataset

The seed data contains 4 products per BU. This is sufficient to demonstrate all
architectural properties (isolation, federated search, cross-BU discovery) but does not
validate indexing or query performance at production scale.

---

## What Would Be Needed for Production

| Gap | Production requirement |
|---|---|
| Keycloak HA | Two-node active/standby with shared PostgreSQL DB and load balancer in front |
| ERP reconciliation | Automated workflow: detect `pending-fulfilment` orders after ERP recovery, notify customer |
| Outbox pruning | Scheduled job to delete `OutboxMessage` rows where `PublishedAt IS NOT NULL` and `PublishedAt < now() - interval '7 days'` |
| Schema migration coordination | When a BU team changes the product/category schema, the Meilisearch indexer ACL must be updated to match |
| Secret management | Connection strings and OIDC secrets must move from environment variables to a secrets manager (Vault, AWS SSM, etc.) |
| Per-BU monitoring | Each BU needs its own alerting profile so a BU1 circuit-breaker event pages the BU1 team, not the BU2 team |
