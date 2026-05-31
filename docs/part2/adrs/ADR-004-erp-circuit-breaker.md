# ADR-004: BU-local ERP Behind Anti-Corruption Layer with Circuit Breaker

**Status:** Accepted  
**Driver:** QA1 (Fault Isolation — Availability)  
**Pressure point:** P3 (inventory is warehouse-centric, not BU-aware)  
**Bounded contexts:** BC2 (BU1 Commerce), BC3 (BU2 Commerce)  
**ADD iteration:** 4

---

## Context

nopCommerce's inventory model is warehouse-centric and carries no store dimension. ADR-001
already isolates BU failure domains at the process and database level, but inventory at
checkout is a synchronous read against an external ERP, so the ERP integration becomes the
second potential entry point for cross-BU fault propagation if it is centralised or shared.
Inventory at checkout cannot be made fully asynchronous: the storefront needs to know
whether a SKU is available before it can confirm an order.

---

## Decision

Each BU runs its own local ERP (or ERP stub in demo). The nopCommerce instance for that
BU integrates with its ERP through a dedicated Anti-Corruption Layer with a Polly circuit
breaker in front.

**Circuit breaker parameters:**
- `FailureThreshold = 5` consecutive failures → OPEN
- `BreakDuration = 30 s` cooldown → HALF-OPEN probe
- On OPEN: serve cached stock snapshot (TTL 5 min), return `StockResult { IsStale=true }`
- On HALF-OPEN: single probe → success closes, failure reopens

**ACL contract:** translates ERP-specific stock/warehouse models into nopCommerce's
inventory abstraction so the rest of the platform never sees ERP-specific concepts.

**Failure-mode UX:** when circuit is OPEN, product pages show a "stock to be confirmed at
fulfilment" banner. No silent failure. Confirmed orders during OPEN enter
`pending-fulfilment` state.

---

## Consequences

QA1 gains its second layer of fault isolation: ADR-001 contains process and database
failures; this ADR contains ERP-integration failures so that a single ERP outage no longer
escalates beyond its own BU. BU autonomy is preserved end-to-end: each ERP keeps its own
database with no boundary-crossing schema.

**Accepted cost:** stock figures during a degraded period can be up to 5 minutes stale
(disclosed in UI); a small fraction of confirmed orders may require reconciliation after
ERP recovery.

---

## Implementation (Part 2)

Plugin: `src/Plugins/Nop.Plugin.Misc.ErpIntegration/`  
Worker (stub): `src/Workers/ErpStub/`

**Circuit breaker** (`ErpCircuitBreaker.cs`): singleton per BU process, thread-safe via
lock. Transitions tracked as OpenTelemetry metrics (`erp_circuit_state`,
`erp_circuit_transitions`).

**Cache:** `IStaticCacheManager`, key `erp.stock.{sku}`, TTL 5 min.

**Stub API:**
```
GET /health          → {"status":"ok"|"degraded","buId":"..."}
GET /stock/{sku}     → {"sku":"...","quantity":N,"warehouseId":"WH-BU{1,2}"}
POST /admin/break    → 503 mode on
POST /admin/recover  → normal mode
```

**Verification (2026-05-31):**
```
ERP BU1 health: {"status":"ok","buId":"bu1"}  ← normal
ERP BU2 health: {"status":"ok","buId":"bu2"}  ← normal

POST /admin/break → ERP BU2 returns 503 on all stock calls
BU2 storefront:  HTTP 200 (circuit absorbs, cached stock + banner)
BU1 storefront:  HTTP 200, live stock unaffected  ← isolation

POST /admin/recover → ERP BU2 returns 200
Circuit: OPEN → HALF-OPEN (probe) → CLOSED (30 s after recovery)
```

---

## Rejected Alternatives

**Single shared ERP for the group:** reproduces the original monolith problem one layer
down — one ERP outage becomes one group-wide outage at the inventory layer.

**Async-only ERP integration:** appealing for write paths but breaks on the read path.
Inventory at checkout is inherently synchronous; events can flow into nopCommerce, but the
price-and-availability read still needs a fast available source.

**Plain timeout without circuit breaker:** a timeout still hits the slow ERP on every
request; the circuit breaker stops calling entirely once the ERP is broken, which is the
actual fault-isolation behaviour.

**Bulkhead pattern (in addition):** not rejected — bulkheads protect connection pools per
BU and the breaker protects the user from ongoing ERP failure; the two complement rather
than substitute each other. Bulkhead is present implicitly through per-BU `HttpClient`
factory isolation.
