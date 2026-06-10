# Setup and Run Instructions — Northstar Living Group Demo

**Scenario A — Federated Commerce After Acquisitions**

---

## Prerequisites

- Docker Engine ≥ 24 with Compose V2 (`docker compose` command)
- 8 GB RAM available for Docker (15 containers)
- Ports 8000, 8080, 8081, 8082, 8083, 5672, 7700, 9001, 9002, 9003, 9101, 9102, 15672, 15692, 9090, 3000 free
  (9101/9102 are the per-BU nopCommerce Prometheus `/metrics` endpoints, served on a
  dedicated port so they stay up even when a BU database is down)

---

## Quick Start

```bash
cd /path/to/AS_Group

# Step 1 — start all containers (builds images on first run)
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d

# Step 2 — wait ~30s for healthchecks, then install and seed
./scripts/install-nop.sh
```

`install-nop.sh`:
1. Waits for both storefronts to accept HTTP
2. Runs the nopCommerce install wizard for BU1 and BU2
3. Seeds BU1 and BU2 product catalogs
4. Installs and configures all plugins
5. Indexes products into Meilisearch

Expected total time: **5–10 minutes** on first run (image build + nopCommerce install wizard).

---

## Service URLs After Startup

| Service | URL | Credentials |
|---|---|---|
| BU1 HomeStyle storefront | http://localhost:8081 | — |
| BU2 WorkSpace storefront | http://localhost:8082 | — |
| Group portal | http://localhost:8000 | — |
| Keycloak admin | http://localhost:8080/admin | admin / admin |
| EspoCRM | http://localhost:8083 | admin / admin |
| RabbitMQ management | http://localhost:15672 | northstar / northstar |
| Meilisearch | http://localhost:7700 | key: `northstar-meili-master-key` |
| ERP BU1 | http://localhost:9001 | — |
| ERP BU2 | http://localhost:9002 | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |

### Test user (Keycloak SSO)

| username | password | email |
|---|---|---|
| alice | alice123 | alice@example.com |

---

## Observability Stack

To include Grafana + Prometheus dashboards:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Open Grafana at http://localhost:3000 → Dashboard: **"Northstar — ADR Evidence"** (11 charts grouped into 4 ADR rows).

Each nopCommerce instance exposes its Prometheus `/metrics` on a dedicated port
(BU1 `http://localhost:9101/metrics`, BU2 `http://localhost:9102/metrics`), isolated
from the storefront pipeline so metrics keep flowing during a BU database outage.
The ADR-001 panel counts orders directly from each BU's PostgreSQL database (datasources
`BU1 Postgres` / `BU2 Postgres`): when a BU DB is stopped its series stops while the
other keeps reporting, which is the data-isolation proof.

---

## Demo Scripts

All demo scripts are in `scripts/`. They orchestrate the failure and recovery sequences
and print timestamped output. Run each in a terminal while watching the Grafana dashboard.

**Run the whole presentation in one go** (ADR-001 → ADR-004 → ADR-005 → ADR-003, in order):
```bash
./scripts/fulldemo.sh
# Prerequisites: stack up (docker compose up -d --build) and ./scripts/install-nop.sh already run
```

The per-ADR scripts below can also be run individually.

### ADR-001: Per-BU isolation

```bash
./scripts/test-isolation.sh
# Stops db_bu1 → verifies BU2 returns HTTP 200 → restarts db_bu1
```

### ADR-002: Keycloak SSO

Open http://localhost:8081/login in a browser. Click "Login with Keycloak (SSO)".
Log in as alice / alice123. Then navigate to http://localhost:8082/login — you should
be redirected to Keycloak, which recognises the session and redirects back without
showing a credential prompt.

Scripted version (no browser, uses curl):
```bash
./scripts/test-sso.sh
# One Keycloak login → authorization codes for BOTH bu1 and bu2 without re-prompting
```

### ADR-003: Outbox durability under CRM outage

```bash
./scripts/demo-outbox.sh
# Pauses CRM consumer → inserts synthetic orders → watches messages accumulate in
# RabbitMQ → unpauses consumer → verifies queue drains to 0 (no data lost)
```

Scripted checks:
```bash
./scripts/test-outbox.sh      # publishes a synthetic order → confirms espocrm_consumer processed it
./scripts/test-durability.sh  # proves the QA5 durability mechanism (durable queue, persistent msgs, no TTL)
```

Shared-customer use case (Scenario A — cross-BU customer view, ADR-001 + ADR-003):
```bash
./scripts/demo-cross-bu-crm.sh
# One order from BU1 and one from BU2 for the SAME customer → both land on a single
# unified EspoCRM profile, with neither BU touching the other's database
```

### ADR-004: ERP circuit breaker

```bash
./scripts/demo-breaker.sh
# Runs k6 load in background → breaks BU1 ERP → watches circuit open →
# observes BU1 storefront stays 200 with cached stock → recovers ERP →
# watches circuit close. Watch Grafana row "ADR-004".
```

Manual version (without k6):
```bash
./scripts/test-erp-failure.sh   # breaks ERP, verifies BU2 banner + BU1 unaffected
./scripts/test-erp-recovery.sh  # recovers ERP, verifies banner disappears
```

### ADR-005: Meilisearch search fallback

```bash
./scripts/demo-search-fallback.sh
# Runs k6 search load → pauses Meilisearch → watches fallback activate →
# unpauses Meilisearch → watches primary path recover. Watch Grafana row "ADR-005".
```

Manual version:
```bash
./scripts/test-search.sh
# Pauses Meilisearch → verifies both BUs return 200 (DB fallback) →
# restarts Meilisearch → verifies fast path recovers
```

### Load testing and observability

Drive synthetic load through a BU so the ADR-004 and ADR-005 panels move in real time.
Requires the observability overlay to be up (Prometheus + Grafana).

```bash
./scripts/run-loadtest.sh search-load          # k6 search load
./scripts/run-loadtest.sh checkout-load        # k6 checkout load
./scripts/run-loadtest.sh product-detail-load  # k6 product-detail load
# k6 runs inside the northstar_default network and remote-writes metrics to Prometheus;
# watch the "Northstar — ADR Evidence" dashboard at http://localhost:3000
```

---

## Stopping the Stack

```bash
docker compose -f docker-compose.yml down
# or with observability:
docker compose -f docker-compose.yml -f docker-compose.observability.yml down
```

To also remove all data volumes (clean reset):
```bash
docker compose -f docker-compose.yml down -v
```

---

## Reproducing the Demo Presentation

One script runs the entire demo end to end:

```bash
./scripts/fulldemo.sh
```

Before starting, open the Grafana dashboard so you can watch the effects live:
**http://localhost:3000/d/northstar-adr-evidence** ("Northstar — ADR Evidence").

It runs four scenarios in order, with a short pause between each:

1. **`test-isolation.sh`** (ADR-001 / QA1) stops BU1's database and restarts it. In the Grafana **ADR-001** row, the BU1 series in "Orders per BU" and "process availability" drops while BU2 keeps reporting, then BU1 recovers.
2. **`demo-breaker.sh`** (ADR-004 / QA1) breaks BU1's ERP and recovers it. In the **ADR-004** row, the breaker state goes 0→2 (OPEN) and the cache-fallback rate rises, then it probes back to 0 (CLOSED).
3. **`demo-search-fallback.sh`** (ADR-005 / QA4) pauses Meilisearch and resumes it. In the **ADR-005** row, the search fallback rate spikes as queries are served from the DB, then returns to the Meilisearch fast path.
4. **`demo-outbox.sh`** (ADR-003 / QA5) pauses the CRM consumer and resumes it. In the **ADR-003** row, the outbox backlog and RabbitMQ queue depth build up while paused, then drain to 0 with no lost messages.

Each storefront stays available (HTTP 200) throughout, in a labelled degraded mode where applicable - that is the point of the pressure scenarios.

Prerequisites: the stack is up (`docker compose ... up -d --build`) and `./scripts/install-nop.sh` has been run. The individual scripts above can also be run one at a time (see [Demo Scripts](#demo-scripts)).

Known limitations to mention in the defense (stale stock while the breaker is OPEN, reconciliation not automated, Keycloak as a login SPOF mitigated by HA in production) are covered in the limitations section of `docs/part2/Report2.pdf`.
