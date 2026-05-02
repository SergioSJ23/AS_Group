# Quality Attribute Scenarios

These five scenarios are the primary architectural drivers for the Northstar Living Group evolution. Each one identifies a real pressure point from the current-state analysis and states what the architecture must guarantee.

Scenarios follow the standard six-part format: Source → Stimulus → Artifact → Environment → Response → Response Measure.

---

## QA1 — Fault Isolation (Availability)

| Part | Description |
|---|---|
| **Source** | BU2's local ERP (ERPNext) crashes or becomes unreachable |
| **Stimulus** | All HTTP calls from BU2's nopCommerce instance to ERPNext time out |
| **Artifact** | BU1 storefront, group-level identity service, shared search index |
| **Environment** | Normal operation, mid-day traffic on both storefronts |
| **Response** | BU1 continues operating without any degradation. BU2 transitions to a degraded-but-open state (cached stock levels, no live inventory confirmation). The group identity service and shared search are unaffected. No cross-BU failure propagation occurs. |
| **Response Measure** | BU1 p95 response time remains under 300ms. BU2 shows cached/stale inventory within 5 seconds of ERP failure detection. Group identity and search remain fully available. Error is visible in BU2 admin dashboard within 30 seconds. |

**Traces to:** P3 (inventory is warehouse-global, needs BU-level isolation), P4 (no coordination mechanism), BC2/BC3 boundary in domain model.

---

## QA2 — BU Pricing Autonomy (Modifiability)

| Part | Description |
|---|---|
| **Source** | BU1 product manager |
| **Stimulus** | Updates pricing rules for 200 products in BU1 (new tier prices, promotional discounts) |
| **Artifact** | BU1 product catalog and pricing; BU2 product catalog and pricing |
| **Environment** | Normal operation; both storefronts live |
| **Response** | BU1 price changes take effect immediately for BU1 customers. BU2 prices and discount rules are completely unaffected. No redeployment, no shared configuration change, no coordination with BU2 required. |
| **Response Measure** | BU1 price update visible to customers within 60 seconds. BU2 pricing queries return unchanged values (verified by automated test). No shared `StoreId=0` setting is modified during the operation. |

**Traces to:** P1 (Product.Price is global), P2 (roles are global), the BU-local pricing ownership decision in BC2/BC3.

---

## QA3 — Federated Identity (Security / Interoperability)

| Part | Description |
|---|---|
| **Source** | Authenticated customer (logged in via Keycloak SSO on BU1) |
| **Stimulus** | Customer navigates to BU2's storefront URL |
| **Artifact** | Authentication session, per-BU customer role assignments |
| **Environment** | Normal operation; Keycloak available |
| **Response** | Customer is recognised in BU2 without re-authentication. BU2-specific roles (e.g. Wholesale, B2B Account) apply to the customer in BU2 only. BU1 roles (e.g. VIP, Trade) are not visible or applied in BU2. nopCommerce on both BUs trusts the OIDC token from Keycloak. |
| **Response Measure** | No login prompt shown on BU2 navigation. Session transition completes in under 2 seconds. Role assignment in BU1 and BU2 are independent and do not interfere with each other (zero role bleed-through in integration tests). |

**Traces to:** P2 (Customer identity fully global, no BU-scoped roles), BC1 (Group Identity), `ExternalAuthenticationRecord` has no StoreId — needs external IdP to own identity.

---

## QA4 — Search Degradation and Recovery (Reliability)

| Part | Description |
|---|---|
| **Source** | Meilisearch instance (shared search infrastructure in BC5) |
| **Stimulus** | Meilisearch becomes temporarily unavailable (process crash or network partition) |
| **Artifact** | Product discovery and search on both BU1 and BU2 storefronts |
| **Environment** | Runtime failure; both storefronts live and receiving traffic |
| **Response** | Both BU storefronts detect the failure and fall back to direct database search within a configured timeout. Search results are slower but available. When Meilisearch recovers, both storefronts resume using it automatically and the index is resynchronised from the last known state. |
| **Response Measure** | Fallback activates within 3 seconds of failure detection. Fallback search returns results in under 5 seconds. Automatic resync completes within 5 minutes of recovery. No manual intervention required. Zero permanent data loss in the index. |

**Traces to:** P4 (no coordination mechanism), BC5 (Shared Infrastructure), the mandatory pressure point in Scenario A (one BU's subsystem degrading without taking down the group experience).

---

## QA5 — Cross-BU Order Visibility (Consistency / Observability)

| Part | Description |
|---|---|
| **Source** | Customer who places an order on BU2's storefront |
| **Stimulus** | Order is confirmed in BU2's nopCommerce instance (`Order.StoreId = 2`) |
| **Artifact** | Group-level customer profile in EspoCRM (BC4) |
| **Environment** | Normal operation; RabbitMQ available; CRM consumer running |
| **Response** | BU2 publishes an order event to the RabbitMQ exchange. The CRM consumer processes it and updates the customer's cross-BU purchase history. If the CRM consumer is temporarily down, the message is persisted in the queue and processed when the consumer recovers. No order data is lost. |
| **Response Measure** | CRM updated within 30 seconds under normal conditions. If consumer is down, message survives in the durable queue for at least 24 hours. After consumer recovery, backlog is processed with no duplicates (idempotent consumer). Customer purchase history in CRM reflects orders from both BU1 and BU2. |

**Traces to:** P4 (no native async coordination), BC4 (Group Customer Profile), `Order.StoreId` already enforced — foundation for per-BU event sourcing.
