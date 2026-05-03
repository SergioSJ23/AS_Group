# ADR-003 - BU-local ERP behind anti-corruption layer with circuit breaker

**Status:** Proposed
**Date:** 2026-05-03
**Driver:** QA1 (Fault Isolation)
**Closes pressure point:** P3 (warehouse-centric inventory, no BU isolation)
**Bounded contexts:** BC2 (BU1 Commerce), BC3 (BU2 Commerce)
**ADD iteration:** 2

## Context

nopCommerce's inventory model is warehouse-centric: `ProductWarehouseInventory` links products to warehouses, but `Warehouse` has no `StoreId` and no BU concept. All BUs draw from the same warehouse pool; any inventory-source outage is automatically a group-wide outage.

QA1 requires: when BU2's local ERP fails, BU1 must be unaffected, and BU2 must keep its storefront open in a degraded-but-honest mode rather than fail closed. This is a cross-BU fault isolation requirement that the current single-warehouse model cannot meet.

## Decision

Each BU operates its own local ERP (ERPNext for BU1, Odoo for BU2 - both open-source, BU-team-friendly). The nopCommerce instance for that BU integrates with the ERP through a dedicated **Anti-Corruption Layer (ACL)** with a **circuit breaker** in front.

- **ACL responsibilities**: translate ERP-specific stock/warehouse models into the nopCommerce `IInventoryProvider` abstraction; isolate ERP terminology and IDs from the commerce domain.
- **Circuit breaker** (Polly or equivalent): closed → open after N consecutive failures or latency above threshold; half-open after a cooldown.
- **Degraded-but-open behaviour** when open:
  - Browse and add-to-cart continue to work using cached stock snapshot (TTL configurable, default 5 minutes).
  - Checkout displays "stock to be confirmed at fulfilment" rather than blocking.
  - Confirmed orders enter a *pending fulfilment* state until ERP recovery.
- **Recovery**: half-open probe; on success, drain pending-fulfilment queue against fresh ERP state and notify customers if reservation cannot be honoured.

The ACL is the only place that knows about the specific ERP. ERP swaps (BU2 moves from Odoo to SAP one day) only touch this component.

## Consequences

**Positive.**
- Satisfies QA1: BU1 is unaware of BU2's ERP outage; BU2 stays partially operational.
- BU autonomy is preserved: each BU operations team owns its ERP, its data, and its upgrade cadence.
- Each ERP has its own DB; no shared DB across boundaries (assignment requirement).
- Failure is observable: circuit-breaker state and pending-fulfilment counts are operational signals.

**Negative.**
- Stock figures shown during a degraded period can be wrong. This is bounded (cache TTL ≤ 5 min) and disclosed to the customer.
- A small fraction of orders placed during outages may not be fulfillable post-recovery; reconciliation policy must be defined (refund or backorder).
- Two ERPs to operate instead of one. Justified: each BU was already running its own pre-acquisition.

**Trade-off accepted.** Honest staleness over false certainty during outages.

## Rejected Alternatives

### A. Single shared ERP for the group
*Rejected.* Reproduces the original monolith problem at the ERP layer. A single ERP outage = group-wide outage. Also forces BU teams to converge on one tool (politically difficult, operationally regressive).

### B. Synchronous ERP call on every page load with no cache
*Rejected.* Every storefront page becomes as available as the slowest ERP. Read latency dominated by ERP latency. Indistinguishable from no isolation at all.

### C. Async-only ERP integration (event-sourced inventory)
*Rejected for this iteration.* Inventory is inherently a synchronous read concern at checkout. Async events are useful for stock updates flowing *into* nopCommerce (and we will use them), but the read path needs a fast, available source - that's the cache + circuit-breaker design.

### D. Replace circuit breaker with simple timeout
*Rejected.* A timeout on every call still hits the slow ERP for every request, just bounded. Circuit breaker stops calling the ERP entirely when it's clearly broken, which is the actual fault-isolation behaviour we need.

### E. Bulkhead pattern instead of circuit breaker
*Considered, kept additionally.* Bulkheads are useful inside the ACL for connection-pool isolation per BU, but they don't replace the breaker. Using both: bulkhead protects nopCommerce thread pool; breaker protects the user from ongoing ERP failure.

## Traceability

| Trace | Reference |
|---|---|
| Driver | doc 04 - QA1 (Fault Isolation) |
| Pressure point closed | doc 02 - P3 |
| Bounded context | doc 03 - BC2, BC3 |
| ADD iteration | doc 06 - Iteration 2 |
| Tactic source | Class slides 03.02 (Availability tactics: circuit breakers, bulkheads, health probes) |
