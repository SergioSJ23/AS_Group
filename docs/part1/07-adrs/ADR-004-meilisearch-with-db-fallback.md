# ADR-004 - Federated Meilisearch with DB fallback strategy

**Status:** Proposed
**Date:** 2026-05-03
**Driver:** QA4 (Search Degradation and Recovery)
**Closes pressure point:** P4 (no group-level coordination), P1 (per-BU catalog ownership) for cross-BU discovery
**Bounded context:** BC5 - Shared Infrastructure
**ADD iteration:** 4

## Context

Cross-BU product discovery - a customer searching for "office desk" should see results from both HomeStyle (BU1) and WorkSpace (BU2) - has no native solution in nopCommerce, because each BU instance owns its own catalog database. A federated search index outside both BUs is required.

QA4 also requires that search remains useful when that index is unavailable: a Meilisearch outage must not take search offline on either BU storefront. The architectural question is *how the system behaves when search degrades*, not just *which search engine to use*.

## Decision

Adopt **Meilisearch** as the federated search index, populated asynchronously from each BU via RabbitMQ events. Storefront search uses a **strategy pattern with a circuit breaker** - Meilisearch is primary, BU-local DB search is fallback - selected per request.

- **Index shape**: single index, every document tagged with `bu_id` and `store_id`. Cross-BU search is the default; UI can filter by `bu_id` for BU-scoped views.
- **Indexing pipeline**: each BU publishes `product.created` / `product.updated` / `product.deleted` events to RabbitMQ (using ADR-002's outbox + broker). A dedicated indexer consumer maintains the Meilisearch index.
- **Read path** on the storefront:
  1. Try Meilisearch with a 1.5 s timeout.
  2. On timeout / error, breaker opens; switch to DB search via `IProductService.SearchProductsAsync` for that BU only (no cross-BU results in fallback).
  3. UI displays a non-blocking notice: "Showing local results - group-wide search temporarily unavailable."
- **Recovery**: breaker half-open every 30 s; one probe; on success, resume Meilisearch as primary.
- **Resync**: indexer consumer drains backlog from RabbitMQ on reconnect; no manual intervention needed.

## Consequences

**Positive.**
- Satisfies QA4: search outage degrades gracefully on both BUs; recovery is automatic; backlog drains from the broker.
- Cross-BU discovery is a real capability for the group, not just architecture-on-paper.
- Indexing reuses ADR-002's broker - no new transport.
- The strategy pattern keeps the fallback testable in isolation.

**Negative.**
- During fallback, results are BU-scoped, not group-scoped. Customer experience is degraded but functional. Disclosure in the UI is mandatory.
- Index drift during long Meilisearch outages - bounded by RabbitMQ retention (durable queues survive broker restart, but not infinite outages).
- Meilisearch requires its own operational learning curve for the team.

**Trade-off accepted.** Fewer features (cross-BU results) under degradation, in exchange for staying open.

## Rejected Alternatives

### A. Elasticsearch
*Rejected for this scope.* Elasticsearch is more powerful (aggregations, complex analyzers) but has materially heavier ops cost (JVM, tuning, multi-node baseline). Meilisearch covers the storefront search use case (typo tolerance, faceting, fast typo-tolerant prefix search) at a fraction of the operational footprint. Swap is possible later if requirements grow.

### B. Database full-text search only (no external index)
*Rejected.* Cross-BU search would require either a shared catalog DB (forbidden by the assignment) or synchronous fan-out queries to every BU (latency scales linearly with BUs, and one slow BU slows every search). Neither acceptable.

### C. Algolia (hosted SaaS)
*Rejected for the demo.* Vendor lock-in, operational cost in a teaching context, data residency questions. Architecturally Algolia would slot in identically to Meilisearch. The plug point (`ISearchProvider` interface in the storefront) is the actual decision; the engine is replaceable.

### D. Synchronous fan-out to per-BU search APIs
*Rejected.* See B above. Compounds latency and creates direct cross-BU coupling.

### E. Push fallback responsibility to the customer ("search unavailable, try later")
*Rejected.* Fail-closed search violates the QA4 spec ("search remains available, slower"). It also damages trust.

## Traceability

| Trace | Reference |
|---|---|
| Driver | doc 04 - QA4 (Search Degradation and Recovery) |
| Bounded context | doc 03 - BC5 |
| ADD iteration | doc 06 - Iteration 4 |
| Tactic source | Class slides 03.02 (Availability: circuit breaker, fallback) |
| Depends on | ADR-002 (RabbitMQ as transport for index events) |
