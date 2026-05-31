# ADR-003: Bridge IEventPublisher to RabbitMQ via Transactional Outbox

**Status:** Accepted  
**Driver:** QA5 (Cross-BU Order Visibility — Consistency); supports QA4  
**Pressure point:** P4 (no cross-process coordination mechanism)  
**Bounded context:** BC5 (Shared Infrastructure)  
**ADD iteration:** 3

---

## Context

nopCommerce already has an in-process event system through `IEventPublisher` with
auto-fired entity events from the repository layer, but it is in-process only, sequential,
and non-durable — none of which satisfies QA5's requirement that order events reach BC4
reliably and survive consumer outages of at least 24 hours without data loss. With per-BU
databases (ADR-001), the in-process publisher cannot reach across BUs at all, so a durable
transport is no longer optional.

---

## Decision

Bridge `IEventPublisher` to RabbitMQ through a transport-layer publisher and a transactional
outbox so that correctness across the nopCommerce database and the broker holds without
needing distributed transactions. Each order is persisted alongside a row in the outbox
table inside the same database transaction. A background relay reads unpublished rows,
publishes them to RabbitMQ, and marks them as published.

**Broker topology:**
- Exchange: `northstar.events` (topic, durable)
- Routing key: `{buId}.order.placed`
- Queue: `northstar.crm.orders` (durable, manual ack)
- Dead-letter: `northstar.crm.orders.dlq`

**Consumer idempotency:** keyed on `(BuId, OrderId)`.

---

## Consequences

Orders survive consumer outages of any practical duration. Every existing
`IEventPublisher` call site stays untouched. The dual-write hazard is removed by
construction: the database commit and the broker publish are never attempted atomically —
the relay is the only writer, and it can be retried safely.

**Accepted cost:** Sub-second consumer-side latency from the two-step publish, an
additional group-level component (RabbitMQ) to run, and an outbox table that needs
periodic pruning.

---

## Implementation (Part 2)

Plugin: `src/Plugins/Nop.Plugin.Misc.OutboxRelay/`  
Worker: `src/Workers/EspoCrmConsumer/`

**Outbox schema** in each BU's DB:
```
OutboxMessage(Id, BuId, EventType, Payload JSON, CreatedAt, PublishedAt nullable)
```

**Relay loop:** `OutboxRelayService` (BackgroundService) polls every 5 s, selects rows
where `PublishedAt IS NULL`, publishes to RabbitMQ topic exchange, sets `PublishedAt`.

**CRM consumer:** `EspoCrmConsumer/Worker.cs` — RabbitMQ BasicConsume with manual ack,
idempotent upsert to EspoCRM REST API, DLQ on 3 retries exhausted.

**Verification (2026-05-31):**
```
Insert synthetic OutboxMessage row at 17:16:31 →
  PublishedAt set at 17:16:34 (within 3 s)

Pause consumer → insert 3 orders → relay publishes to queue →
  RabbitMQ queue depth: 3 (consumer paused)
Unpause consumer →
  Queue depth: 0 (total_acked: 3) — no data lost
  All 4 outbox rows: published: 4, unpublished: 0
```

---

## Rejected Alternatives

**Synchronous HTTP call from each BU to CRM on order placement:** couples order placement
to CRM availability; a CRM outage turns into either failed orders or silently dropped
updates. Both break QA5 directly.

**Apache Kafka:** strongest in high-throughput streaming and long-window replay; neither
matches transactional commerce volumes. RabbitMQ's per-message ack and dead-letter exchange
map far more cleanly onto the "process each order exactly once with retries" shape.

**CRM scrapes each BU's database (polling integration):** clear violation of the
no-shared-database rule and a leak of BU schema into the CRM.

**Publish to RabbitMQ directly without outbox:** reintroduces the dual-write problem —
a crash between DB commit and broker publish either loses or ghosts the event.
