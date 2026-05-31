# ADR-005: Federated Meilisearch with DB Fallback Strategy

**Status:** Accepted  
**Driver:** QA4 (Search Degradation and Recovery — Reliability)  
**Pressure points:** P4 (cross-BU coordination), P1 (cross-BU discovery)  
**Bounded context:** BC5 (Shared Infrastructure)  
**ADD iteration:** 5

---

## Context

Cross-BU product discovery has no native solution in nopCommerce because each BU instance
owns its own catalog database (ADR-001). A federated search index that lives outside both
BUs is required for a customer to discover products across the group. QA4 also imposes a
graceful-degradation requirement: search must remain useful when the index itself is
unavailable, otherwise an outage in shared infrastructure cascades back into every BU's
storefront.

---

## Decision

Adopt Meilisearch as the federated search index, populated asynchronously from each BU
through ADR-003's outbox and broker so that no synchronous fan-out is needed at write
time. Storefront search runs through a strategy pattern with a circuit breaker:

- **Primary path:** Meilisearch query (timeout: 1.5 s)
- **Fallback path:** BU-local PostgreSQL full-text search (activated on timeout or circuit OPEN)
- **Recovery:** circuit probes half-open at 30-second intervals; on success, BU resumes Meilisearch and drains its event backlog from RabbitMQ

**Index document:**
```json
{ "id": "{buId}-{productId}", "productId": N, "buId": "bu1|bu2",
  "name": "...", "description": "...", "sku": "..." }
```

`buId` is a filterable attribute. Cross-BU search defaults to no filter (all BUs). Per-BU
search filters by `buId`.

---

## Consequences

Cross-BU product discovery becomes a real capability rather than a UI illusion. The
strategy pattern keeps the fallback path testable in isolation. The broker investment from
ADR-003 is reused at no extra operational cost for the re-index pipeline.

**Accepted cost:** fallback results during an index outage are BU-scoped rather than
group-scoped (disclosed in the UI); index drift is bounded by RabbitMQ's retention window
and reconciles on reconnect.

---

## Implementation (Part 2)

Plugin: `src/Plugins/Nop.Plugin.Search.Meilisearch/`

**`MeilisearchSearchProvider`** implements `ISearchProvider`:
```csharp
SearchProductsAsync(keywords):
  Try:
    Meilisearch HTTP query (CancellationTokenSource 1.5 s)
    → return List<int> product IDs
  On BrokenCircuitException | OperationCanceledException:
    FallbackSignal.Trigger()    ← ViewData["SearchFallback"]=true → banner
    throw                       ← nopCommerce core falls back to DB SQL search
```

**Indexer:** `MeilisearchIndexer.BulkIndexAsync()` called on plugin install. Per-product
upserts via `ProductSavedConsumer` (event-driven maintenance).

**nopCommerce core patch** (`src/Libraries/Nop.Services/Catalog/ProductService.cs`):
3 targeted patches to allow `ISearchProvider` results to replace the SQL query path
correctly (linq2db cannot translate hybrid LINQ trees mixing DB and in-memory results).

**Verification (2026-05-31):**
```
Meilisearch healthy:
  Index: products, documents: 8 (4 BU1 + 4 BU2)
  Search "chair" → 1 hit in 0 ms (server-side), 27 ms round-trip

Cross-BU federated query (no filter):
  → 8 hits (4 BU1 + 4 BU2) in <5 ms

docker pause northstar-meilisearch-1:
  BU1 GET /search?q=sofa  → HTTP 200 in 4482 ms (DB fallback, available)
  BU2 GET /search?q=chair → HTTP 200 in 4302 ms (DB fallback, available)

docker unpause northstar-meilisearch-1:
  BU1 GET /search?q=sofa  → HTTP 200 in 249 ms  (Meilisearch resumed)
  Recovery: automatic, no manual intervention
```

---

## Rejected Alternatives

**Elasticsearch:** satisfies the same architectural shape at significantly heavier
operational cost (JVM tuning, multi-node baseline). Meilisearch covers the storefront
search use case at a fraction of the operational footprint.

**Database full-text search alone:** would either force a shared catalog database
(contradicts ADR-001) or a synchronous fan-out per BU (compounds latency and creates
direct cross-BU coupling).

**Hosted SaaS (Algolia):** set aside on the same grounds as hosted IdPs in ADR-002 —
vendor lock-in, recurring cost, and data-residency questions. The plug point is the
actual decision; the engine is replaceable.

**"Search unavailable" message on Meilisearch failure:** rejected as fail-closed behaviour
that violates QA4 and erodes user trust without any architectural benefit.
