# Northstar - Federated nopCommerce (Group Assignment)

This repository contains the team's implementation for the **Group Assignment** of the Software Architecture course: an architectural evolution of nopCommerce from a single-tenant monolith into a federated, multi-Business-Unit commerce platform.

The vendor's original project README is preserved in [`README.Original.md`](README.Original.md).

---

## 1. What was implemented

Five Architectural Decision Records (ADR-001 to ADR-005) plus a transactional outbox / CRM integration. Each ADR is realised by concrete code, a docker-compose service, and a smoke-test script under `scripts/`.

| ADR | Concern | Mechanism | Smoke test |
|---|---|---|---|
| ADR-001 | Per-BU process and data isolation | Two `nop_bu1` / `nop_bu2` containers + two PostgreSQL databases (`db_bu1`, `db_bu2`) with no shared connection | `scripts/test-isolation.sh` |
| ADR-002 | Group-wide SSO | Keycloak (realm `northstar`) acting as OIDC IdP for both BUs via the `Nop.Plugin.ExternalAuth.Keycloak` plugin | `scripts/test-sso.sh` |
| ADR-003 | Reliable cross-BU events to the CRM | Transactional outbox in each BU DB, relay publisher to RabbitMQ, dedicated `EspoCrmConsumer` worker writing to EspoCRM | `scripts/test-outbox.sh` |
| ADR-004 | BU-local ERP integration that must not bring the storefront down | `Nop.Plugin.Misc.ErpIntegration` calling an `ErpStub` worker per BU, guarded by an in-process circuit breaker | `scripts/test-erp-failure.sh`, `scripts/test-erp-recovery.sh` |
| ADR-005 | Federated product search with graceful DB fallback | `Nop.Plugin.Search.Meilisearch` indexing per-BU into a shared Meilisearch instance, with vendor patches in `ProductService` so the storefront falls back to the SQL search when Meilisearch is unreachable | `scripts/test-search.sh` |

---

## 2. Repository layout (assignment-relevant parts)

```
.
├── docker-compose.yml              Full federated stack (8 services, see §4)
├── Dockerfile                      nopCommerce build (used by nop_bu1 / nop_bu2)
├── scripts/
│   ├── install-nop.sh              Idempotent installer: seeds both BUs, installs plugins,
│   │                               wires Keycloak + Meilisearch + ERP + RabbitMQ settings
│   ├── test-isolation.sh           ADR-001 verification
│   ├── test-sso.sh                 ADR-002 verification
│   ├── test-outbox.sh              ADR-003 verification
│   ├── test-erp-failure.sh         ADR-004 circuit-breaker open path
│   ├── test-erp-recovery.sh        ADR-004 circuit-breaker close path
│   └── test-search.sh              ADR-005 live / fallback / recovery
├── spike/
│   ├── docker-compose.spike.yml    Original Keycloak-only spike (kept for reference)
│   ├── keycloak/realm-northstar.json  Realm pre-loaded with bu1/bu2 OIDC clients + test user
│   ├── pg-init/01-citext.sql       Postgres extension needed by nopCommerce migrations
│   ├── HOW_TO_TEST.md              Walkthrough for the SSO spike
│   └── SPIKE_REPORT.md             Spike write-up (ADR-002)
├── src/
│   ├── Libraries/Nop.Services/Catalog/ProductService.cs
│   │       Vendor file patched for ADR-005 (linq2db / in-memory-results compatibility)
│   ├── Plugins/
│   │   ├── Nop.Plugin.ExternalAuth.Keycloak/   ADR-002 OIDC integration
│   │   ├── Nop.Plugin.Misc.OutboxRelay/        ADR-003 outbox writer + RabbitMQ publisher
│   │   ├── Nop.Plugin.Misc.ErpIntegration/     ADR-004 ERP client + circuit breaker
│   │   └── Nop.Plugin.Search.Meilisearch/      ADR-005 search provider + indexer
│   └── Workers/
│       ├── EspoCrmConsumer/        ADR-003 RabbitMQ -> EspoCRM REST relay
│       └── ErpStub/                ADR-004 BU-local fake ERP (toggleable failure mode)
└── docs/part1/                     Part 1 deliverable PDFs (report + images)
```

The plugins live inside the original `src/Plugins/` tree so they are picked up by the standard nopCommerce plugin loader. The vendor PRs/forks of upstream nopCommerce files are limited to a single file (`ProductService.cs`); every other change is additive.

---

## 3. New first-party components

### 3.1 `Nop.Plugin.ExternalAuth.Keycloak` (ADR-002)
- Implements `IExternalAuthenticationMethod` and registers `AddOpenIdConnect` against the per-BU client (`bu1-nopcommerce` / `bu2-nopcommerce`).
- `ResponseMode = "query"` is used instead of the default `form_post` so the OIDC correlation cookie (SameSite=Lax) survives the redirect.
- Built with `Microsoft.NET.Sdk.Web` because the OIDC handler is part of the ASP.NET Core shared framework and is not redistributable as a normal NuGet.

### 3.2 `Nop.Plugin.Misc.OutboxRelay` (ADR-003)
- `OutboxWriter` persists outbound integration events into an `OutboxMessage` table in the BU's own database, inside the same transaction as the business write.
- `OrderPlacedConsumer` hooks the nopCommerce `OrderPlacedEvent` and inserts the event row.
- `OutboxRelayService` is a hosted background service that polls the outbox table and ships rows to RabbitMQ via `RabbitMqPublisher`.
- Each BU writes to its own outbox: cross-BU coupling is only via the message broker.

### 3.3 `EspoCrmConsumer` worker (ADR-003)
- .NET worker service subscribed to the RabbitMQ exchange populated by both BUs.
- Translates `OrderMessage` payloads into EspoCRM REST calls (`EspoCrmClient`) so EspoCRM becomes the single source of truth for customer / order history across BUs.

### 3.4 `Nop.Plugin.Misc.ErpIntegration` + `ErpStub` (ADR-004)
- `ErpStockService` calls the BU-local `ErpStub` worker over HTTP for stock lookups.
- `ErpCircuitBreaker` opens after consecutive failures, fast-fails for a cool-down window, then probes for recovery. While open the storefront degrades gracefully via `ErpStockBannerViewComponent` instead of throwing.
- `ErpStub` exposes a `/health` endpoint and a toggleable failure mode used by the recovery / failure scripts.

### 3.5 `Nop.Plugin.Search.Meilisearch` (ADR-005)
- `MeilisearchSearchProvider` implements the nopCommerce search-provider contract; documents use a composite `{buId}-{productId}` ID and a filterable `buId` attribute so the shared index can be queried per-BU without cross-tenant leakage.
- `ProductSavedConsumer` listens to `EntityInserted/Updated/DeletedEvent<Product>` so the index stays in sync without a batch reindex job.
- `MeilisearchClient` and `MeilisearchIndexer` wrap the REST API and the bulk upsert / delete operations.
- `SearchFallbackBannerViewComponent` surfaces an "operating in degraded search mode" banner whenever the provider trips into the DB-backed fallback path.
- `FallbackSignal` / `IFallbackSignal` carry the "search provider threw" decision out of `ProductService` into the view layer.

#### Vendor patches in `src/Libraries/Nop.Services/Catalog/ProductService.cs`
nopCommerce 5.0 mixes `linq2db` queries with in-memory `IEnumerable` results coming from a search provider, which produces hybrid expression trees that `linq2db` cannot translate. Three minimally invasive patches were applied:
1. Gate the SKU / category-name / manufacturer-name / product-tag `Union` blocks with `&& runStandardSearch` so they are skipped when a search provider supplied the candidate set.
2. Replace the `productsQuery` join against `productsByKeywords` with a materialised `keywordProductIds.Contains(p.Id)` filter.
3. Replace the provider-ordering `GroupJoin` with an in-memory dictionary lookup over the materialised result list (`new Dictionary<int, int>` keyed by product id, value = provider rank), preserving the `ProductSortingEnum.Position` semantics.

These are the only edits to upstream code; everything else lives in plugins.

---

## 4. Runtime topology (`docker-compose.yml`)

Single `docker compose up` brings up the eight services that back ADR-001..005:

```
keycloak (8080) ──── shared IdP for both BUs
db_bu1 (Postgres)    db_bu2 (Postgres)
nop_bu1 (8081)  ──── nop_bu2 (8082)
rabbitmq (5672/15672)
meilisearch (7700)
espocrm_db (MariaDB) + espocrm (8083)
espocrm_consumer (worker, no port)
erp_bu1 (9001) + erp_bu2 (9002)
```

Per-BU isolation is enforced by environment variables (each BU only knows its own `db_*`, `erp_*`, OIDC client) and by separate App_Data volumes (`nop_bu1_app_data`, `nop_bu2_app_data`). The realm import file under `spike/keycloak/` is mounted into Keycloak so OIDC clients and the test user exist on the first boot.

---

## 5. Running and verifying the assignment

1. `docker compose up --build` and wait until all services report healthy.
2. `./scripts/install-nop.sh` to seed both BUs, install the plugins, and wire the Keycloak / Meilisearch / ERP / RabbitMQ configuration. The script is idempotent.
3. Run the smoke tests for each ADR (see table in §1). Each script prints a PASS/FAIL line per check.

URLs once the stack is up:

- BU1 storefront: <http://localhost:8081>
- BU2 storefront: <http://localhost:8082>
- Keycloak admin: <http://localhost:8080> (admin / admin)
- RabbitMQ management: <http://localhost:15672> (northstar / northstar)
- Meilisearch: <http://localhost:7700>
- EspoCRM: <http://localhost:8083> (admin / admin)
- ERP stubs: <http://localhost:9001/health>, <http://localhost:9002/health>

---

## 6. Documentation deliverables

The written deliverables for Part 1 (current-state analysis, quality-attribute scenarios, framework choice, target architecture, ADRs, risk plan, spike report) are bundled in `docs/part1/` as `report/AS_Project-2.pdf`. The spike report is also available as Markdown under `spike/SPIKE_REPORT.md`.
