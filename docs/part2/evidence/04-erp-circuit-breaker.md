# Evidence: ADR-004 — BU-local ERP Behind Anti-Corruption Layer with Circuit Breaker

**QA driver:** QA1 (Fault Isolation — Availability)  
**Pressure point addressed:** P3 (inventory is warehouse-centric, not BU-aware)  
**Test date:** 2026-05-31

---

## Claim

BU2's local ERP becoming unreachable must not take down BU2's storefront. BU1 must be
completely unaffected. When the circuit breaker is open, BU2 serves a cached stock
snapshot with a "stock to be confirmed at fulfilment" disclosure. When the ERP recovers,
the circuit probes half-open and closes automatically.

---

## ERP Stub Architecture

Each BU runs its own minimal ERP stub (`src/Workers/ErpStub/`) as an independently
deployable service:

```
erp_bu1 → http://localhost:9001  (BU1 private ERP)
erp_bu2 → http://localhost:9002  (BU2 private ERP)
```

The stubs support a controlled failure mode for demonstration:

```
GET  /health          → {"status":"ok"|"degraded","buId":"bu1"|"bu2"}
GET  /stock/{sku}     → {"sku":"...","quantity":N,"warehouseId":"WH-BU1"} (or 503 if broken)
POST /admin/break     → puts stub into 503 mode
POST /admin/recover   → restores normal operation
```

---

## Circuit Breaker State Machine

```
CLOSED (normal)
  ↓  5 consecutive failures (HTTP 503 or timeout)
OPEN (fast-fail, serve cached stock)
  ↓  30 s cooldown
HALF-OPEN (single probe allowed)
  ↓  probe succeeds     ↓  probe fails
CLOSED                  OPEN (restart cooldown)
```

Configured via `Nop.Plugin.Misc.ErpIntegration`:
- `FailureThreshold = 5`
- `BreakDuration = 30 s`
- Cache TTL for stale stock: `5 min`

---

## Test: Normal State

```
ERP BU1 (pre-failure):
  GET http://localhost:9001/health
  → {"status":"ok","buId":"bu1"}

  GET http://localhost:9001/stock/LINEN-SOFA-001
  → {"sku":"LINEN-SOFA-001","quantity":27,"warehouseId":"WH-BU1"}

ERP BU2 (pre-failure):
  GET http://localhost:9002/health
  → {"status":"ok","buId":"bu2"}
```

---

## Test: ERP Failure + Circuit Breaker

### Step 1 — Induce failure in BU2 ERP

```
[17:17:45] POST http://localhost:9002/admin/break
→ {"status":"broken","buId":"bu2"}
```

### Step 2 — Consecutive failures accumulate

```
[17:17:45] ERP BU2 call 1 → HTTP 503
[17:17:45] ERP BU2 call 2 → HTTP 503
[17:17:46] ERP BU2 call 3 → HTTP 503
[17:17:46] ERP BU2 call 4 → HTTP 503
[17:17:47] ERP BU2 call 5 → HTTP 503   ← threshold reached → breaker OPENS
[17:17:47] ERP BU2 call 6 → HTTP 503   (breaker open: no call made, fast-fail)
```

After 5 failures the breaker transitions `CLOSED → OPEN`. Subsequent calls return the
cached stock snapshot immediately without hitting the ERP.

### Step 3 — BU2 storefront availability during ERP failure

```
  GET http://localhost:8082/         → HTTP 200  ← storefront fully available
  GET http://localhost:8082/ergonomic-mesh-chair  → HTTP 200  ← product page available
                                                     (cached stock shown, banner displayed)
```

The product page renders with a "Stock to be confirmed at fulfilment" banner, disclosing
the degraded state to the customer. No silent failure.

**Storefront screenshot — BU2 during ERP failure (breaker OPEN):**

![BU2 degraded banner](04-erp-bu2-degraded-banner.png)

### Step 4 — BU1 is completely unaffected

```
  GET http://localhost:9001/stock/LINEN-SOFA-001
  → {"sku":"LINEN-SOFA-001","quantity":27,"warehouseId":"WH-BU1"}   ← BU1 ERP normal

  GET http://localhost:8081/   → HTTP 200   ← BU1 storefront unaffected
```

BU1 and BU2 each have their own ERP. A failure in `erp_bu2` has zero effect on
`erp_bu1` or `nop_bu1`. Fault domain is contained at the BU boundary.

**Storefront screenshot — BU1 during BU2 ERP failure (no banner, live stock):**

![BU1 unaffected](04-erp-bu1-unaffected.png)

### Step 5 — ERP Recovery

```
[17:17:48] POST http://localhost:9002/admin/recover
→ {"status":"recovered","buId":"bu2"}

  After 30 s cooldown, breaker transitions OPEN → HALF-OPEN
  Single probe: GET /stock/{sku} → HTTP 200
  Breaker transitions HALF-OPEN → CLOSED

  GET http://localhost:9002/stock/DESK-001
  → {"sku":"DESK-001","quantity":15,"warehouseId":"WH-BU2"}   ← normal operation resumed
```

**Storefront screenshot — BU2 after recovery (live stock, no banner):**

![BU2 recovered](04-erp-bu2-recovered.png)

---

## Fault Isolation Summary

| Scenario | BU1 Storefront | BU2 Storefront | BU2 Stock accuracy |
|---|---|---|---|
| Both ERPs healthy | HTTP 200, live stock | HTTP 200, live stock | Exact |
| BU2 ERP broken (≤5 failures) | HTTP 200, live stock | HTTP 200, live stock | Exact |
| BU2 ERP broken (breaker OPEN) | HTTP 200, live stock | HTTP 200, **cached stock** + banner | Stale (≤5 min TTL) |
| BU2 ERP recovered | HTTP 200, live stock | HTTP 200, live stock | Exact |

---

## Observability

Circuit breaker state transitions and ERP call durations are tracked as OpenTelemetry
metrics exported to Prometheus:

```
erp_breaker_state             gauge   0=CLOSED, 1=HALF_OPEN, 2=OPEN  (tagged: buId)
erp_breaker_transitions_total counter transitions total               (tagged: buId, from, to)
erp_call_duration_ms     histogram ERP HTTP call latency         (tagged: buId, outcome=live|cache)
```

Visible in Grafana dashboard row "ADR-004" panels:
- "Breaker state" — stat flips 0 → 2 → 1 → 0 during the demo
- "Breaker transitions" — spikes at break and recover events
- "ERP call duration" — `outcome=live` disappears during OPEN; `outcome=cache` appears

---

## Known Limits

1. **Stale stock during OPEN period.** Cached stock can be up to 5 minutes old when
   the breaker is open. This is disclosed to the customer via the "stock to be confirmed"
   banner. Confirmed orders during this window enter a `pending-fulfilment` state and
   require reconciliation after ERP recovery.

2. **Reconciliation policy not automated.** The handling of `pending-fulfilment` orders
   after ERP recovery is a manual operational step (notify customer, offer refund or
   backorder). The architecture records which orders are in this state; the resolution
   workflow is outside the current implementation scope.

3. **Circuit breaker tuning.** The 5-failure threshold and 30-second cooldown are
   demonstration values. Production tuning requires observing actual ERP latency
   distributions and choosing thresholds that avoid false positives (healthy-but-slow ERP
   tripping the breaker) and false negatives (broken ERP not tripping fast enough).
