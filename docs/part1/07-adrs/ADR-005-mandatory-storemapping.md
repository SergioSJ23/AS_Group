# ADR-005 - Mandatory `StoreMapping` enforcement and BU-scoped pricing

**Status:** Proposed
**Date:** 2026-05-03
**Driver:** QA2 (BU Pricing Autonomy)
**Closes pressure points:** P1 (`Product.Price` global), P6 (`IgnoreStoreLimitations` global bypass), P7 (ACL is role-scoped only)
**Bounded contexts:** BC2 (BU1 Commerce), BC3 (BU2 Commerce)
**ADD iteration:** 5

## Context

Three nopCommerce defaults work against the federation scenario:

1. `Product.Price` is a single global decimal (`Domain/Catalog/Product.cs:401`). Per-BU pricing requires the optional `TierPrice` mechanism with `StoreId != 0`.
2. `CatalogSettings.IgnoreStoreLimitations` (`CatalogSettings.cs:390`) is a single boolean. When set to `true`, `ApplyStoreMapping` short-circuits at `StoreMappingService.cs:95` and silently disables every catalog isolation rule across the group.
3. Products without `LimitedToStores = true` are visible in **every** store by default. Catalog isolation is opt-in; the absence of explicit mapping means *visible everywhere*.

QA2 requires that BU1 can update prices for 200 products without affecting BU2. With the current defaults, that requires either trusting an admin convention or accepting that one toggle (P6) can erase all isolation. Neither is acceptable for a federated platform.

## Decision

Enforce store-scoped catalog and pricing at the database and runtime level, removing the opt-in nature:

1. **Disable `IgnoreStoreLimitations` permanently.** Set to `false` at startup; remove the admin UI toggle for it; document that it must not be enabled in a federated deployment.
2. **Mandatory `StoreMapping` on every product.** A startup integrity check fails fast if any product has `LimitedToStores = false` or no `StoreMapping` rows. Migration: a one-time admin script assigns every existing product to at least one store.
3. **BU-scoped `TierPrice` becomes the canonical price for that BU.** The base `Product.Price` is treated as a fallback / template. Per-BU price queries always evaluate `TierPrice` with `StoreId == bu_store_id` first.
4. **Per-BU role naming convention.** BU-specific roles are prefixed (`bu1.wholesale`, `bu2.wholesale`); `AclRecord.CustomerRoleId` continues to be used as-is, with the prefix providing the BU dimension. This avoids invasive schema change to `CustomerRole` for the Part 1 scope.

## Consequences

**Positive.**
- Closes P6 - no single switch can collapse BU isolation.
- Satisfies QA2: BU1 price updates touch only BU-1 `TierPrice` rows; BU2 reads do not see them.
- The migration produces a clean catalog state where every product has explicit BU ownership.
- Uses existing nopCommerce mechanisms - no schema changes for Part 1.

**Negative.**
- Group-level "publish this product to every BU" becomes an explicit multi-BU operation in admin. Tooling needed.
- Existing test fixtures and seed data assume opt-in mapping; migration scripts must update them.
- The role-prefix convention is a workaround. A proper fix (`CustomerRole.StoreId`) is deferred to a future ADR - flagged as tech debt.

**Trade-off accepted.** Operational overhead at product creation time (must select target BUs explicitly), in exchange for guaranteed isolation.

## Rejected Alternatives

### A. Add `Product.StoreId` directly to the `Product` entity
*Rejected.* Schema change to a core entity ripples through migrations, the admin UI, and every plugin that touches `Product`. The existing `StoreMapping` bridge already supports the same semantics with no schema change. Use what's already there.

### B. Build an external Price/Catalog service
*Rejected for this iteration.* Extracting pricing/catalog from nopCommerce is a major architectural move - moves data, breaks the admin UI, requires bidirectional sync. The existing `StoreMapping` + `TierPrice` seams are sufficient for the scenario. Extraction can be revisited later if BU autonomy outgrows what the seams allow.

### C. Leave `IgnoreStoreLimitations` as an admin-controllable toggle
*Rejected.* The whole point of a federated platform is that no single admin action can collapse isolation across BUs. A toggle that can do so silently is a latent group-wide outage waiting to happen.

### D. Per-BU separate database (full data partition)
*Rejected.* Conflates two concerns: federation (BU autonomy) and persistence (one DB per BU). Each BU **does** get its own DB in the deployment view (doc 06), but that's because each BU runs its own nopCommerce instance - not because a shared instance with shared DB couldn't enforce isolation. Inside one nopCommerce instance, `StoreMapping` is the right tool.

### E. Use `AclRecord` to scope products by BU instead of `StoreMapping`
*Rejected.* `AclRecord` filters by `CustomerRoleId`, not by store. Misusing it for BU isolation conflates "who can see this" with "which BU sells this" - two different concerns that will eventually collide.

## Traceability

| Trace | Reference |
|---|---|
| Driver | doc 04 - QA2 (BU Pricing Autonomy) |
| Pressure points closed | doc 02 - P1, P6, P7 |
| Bounded contexts | doc 03 - BC2, BC3 |
| ADD iteration | doc 06 - Iteration 5 |
| Existing seam | `Domain/Stores/StoreMapping.cs`, `Catalog/TierPrice.cs`, `Services/Stores/StoreMappingService.ApplyStoreMapping` |
