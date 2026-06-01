# Setup and Run Instructions — Northstar Living Group Demo

**Scenario A — Federated Commerce After Acquisitions**

---

## Prerequisites

- Docker Engine ≥ 24 with Compose V2 (`docker compose` command)
- 8 GB RAM available for Docker (15 containers)
- Ports 8000, 8080, 8081, 8082, 8083, 5672, 7700, 9001, 9002, 9003, 15672, 9090, 3000 free

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

Open Grafana at http://localhost:3000 → Dashboard: **"Northstar — ADR Evidence"** (19 panels).

---

## Demo Scripts

All demo scripts are in `scripts/`. They orchestrate the failure and recovery sequences
and print timestamped output. Run each in a terminal while watching the Grafana dashboard.

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

### ADR-003: Outbox durability under CRM outage

```bash
./scripts/demo-outbox.sh
# Pauses CRM consumer → inserts synthetic orders → watches messages accumulate in
# RabbitMQ → unpauses consumer → verifies queue drains to 0 (no data lost)
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

The recommended 15-minute demo order:

1. **(2 min)** Architecture overview — point at Grafana dashboard, identify 8 subsystems
2. **(3 min)** UC1 — SSO: log in on BU1 as alice, navigate to BU2, no re-prompt. Show two Customer rows in DB with same ExternalIdentifier but different roles.
3. **(2 min)** UC2 — BU-specific catalog: search "sofa" on BU1 (HomeStyle), "desk" on BU2 (WorkSpace). Show Meilisearch cross-BU query returns both.
4. **(4 min)** Pressure point — run `./scripts/demo-breaker.sh` while watching Grafana "ADR-004". Break BU2 ERP → circuit opens → storefront stays up with cached stock banner → recover.
5. **(2 min)** Outbox durability — run `./scripts/demo-outbox.sh`. Show messages surviving consumer pause.
6. **(2 min)** Limits defense — reference `docs/part2/evidence/known-limitations.md`. Known: stale stock during OPEN, reconciliation not automated, Keycloak SPOF (mitigated by HA in production).
