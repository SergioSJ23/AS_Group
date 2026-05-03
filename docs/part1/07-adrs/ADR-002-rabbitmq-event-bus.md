# ADR-002 - Bridge `IEventPublisher` to RabbitMQ for cross-BU events

**Status:** Proposed
**Date:** 2026-05-03
**Driver:** QA5 (Cross-BU Order Visibility), supports QA4
**Closes pressure point:** P4 (no cross-process coordination mechanism)
**Bounded context:** BC5 - Shared Infrastructure
**ADD iteration:** 3

## Context

nopCommerce already has an in-process event system: `IEventPublisher` (Nop.Core) with `IConsumer<T>` handlers (Nop.Services), and `EntityRepository<T>` automatically fires `EntityInsertedEvent<T>`, `EntityUpdatedEvent<T>`, `EntityDeletedEvent<T>` on every CRUD operation. This system is **in-process only, sequential, and non-durable** (doc 02 P4). It cannot satisfy QA5, which requires order events from BU1 and BU2 to reach the group customer profile (BC4) reliably, surviving consumer outages of at least 24 hours.

The decision space is *how* to extend the event system across processes, not *whether* to add eventing - the abstraction already exists.

## Decision

Bridge `IEventPublisher` to **RabbitMQ** by adding a new transport-layer publisher that forwards selected events through a **transactional outbox**. The outbox preserves correctness across the nopCommerce DB and the broker without distributed transactions.

- **Outbox table** in each BU's nopCommerce database: `(id, aggregate_type, aggregate_id, event_type, payload, occurred_at, published_at NULL)`
- **Atomic write**: order persistence and outbox row are committed in the same transaction
- **Relay worker** (background service): reads unpublished rows in order, publishes to RabbitMQ, marks `published_at`
- **RabbitMQ topology**: topic exchange per concern (`order.events`, `product.events`); routing keys carry `bu1.*` / `bu2.*`
- **Consumer side**: durable queues, manual ack, dead-letter on parse or processing error after N retries
- **Idempotency**: every event carries `(aggregate_id, version)`; consumers upsert by that key

Cross-process events bridged in the first phase: `OrderPlacedIntegrationEvent`, `OrderPaidIntegrationEvent`, `ProductPriceChangedIntegrationEvent`. In-process consumers continue to receive `EntityInsertedEvent<Order>` etc. unchanged.

## Consequences

**Positive.**
- Survives a CRM consumer outage of any duration: messages persist on disk in RabbitMQ, redelivered on reconnect.
- The existing `IEventPublisher` call sites do not change. Only the transport changes.
- Outbox eliminates the dual-write problem (DB commit succeeds, broker publish fails ⇒ ghost order in customer profile).
- A reliable broker also unlocks ADR-004 (search re-index events) at zero additional infrastructure cost.

**Negative.**
- Two-step publish (DB then broker via relay) introduces visible latency on the consumer side: typically <1s, bounded by relay tick + broker round-trip.
- Operational complexity: RabbitMQ is now a group-level component to monitor.
- Outbox table grows; needs a periodic prune job for `published_at IS NOT NULL` rows older than retention window (e.g. 7 days).

**Trade-off accepted.** Eventual consistency between BU order state and group profile, with bounded staleness (<30s normal, <24h under degraded consumer). This is the QA5 specification, not a side effect.

## Rejected Alternatives

### A. Synchronous HTTP call from BU to CRM on order placement
*Rejected.* Couples order placement to CRM availability. A CRM outage would either fail orders (unacceptable for revenue) or silently drop updates (worse). Violates QA5.

### B. Kafka instead of RabbitMQ
*Rejected for this scope.* Kafka excels at high-throughput event streaming and replay. Our volume is transactional commerce events (~order/sec scale), not analytics. RabbitMQ's per-message ack + DLX is a better fit for "process each order event exactly once with retries". Kafka can replace RabbitMQ later without changing the publish contract if event volume changes the equation.

### C. Database-polling integration (CRM polls BU DBs for new orders)
*Rejected.* Pull-based integration leaks BU schema to the CRM, breaks the "no shared database across boundaries" rule from the assignment, and scales badly with more BUs.

### D. Use the in-process `IEventPublisher` directly with cross-process consumer
*Rejected - not technically possible.* `IEventPublisher` resolves consumers via in-process DI (`EngineContext.Current.ResolveAll<>()`); it has no transport. Calling it from one process does not deliver to another.

### E. Publish to RabbitMQ directly inside the order service (no outbox)
*Rejected.* Creates a dual-write problem: DB commit + broker publish are not atomic. A crash between them either loses the event (broker publish skipped) or ghosts the order (broker publish succeeds, DB rolls back). The outbox is the standard solution.

## Traceability

| Trace | Reference |
|---|---|
| Driver | doc 04 - QA5 (Cross-BU Order Visibility) |
| Pressure point closed | doc 02 - P4 |
| Bounded context | doc 03 - BC5 |
| ADD iteration | doc 06 - Iteration 3 |
| Existing seam | `Nop.Core.Events.IEventPublisher`, `EntityRepository<T>` lifecycle events |
