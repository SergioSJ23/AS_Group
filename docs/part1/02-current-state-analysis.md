# Current-State Analysis of nopCommerce

## Architecture Overview

nopCommerce follows an **onion architecture** built on C# / ASP.NET Core. Dependencies only point inward; outer layers may reference any inner layer directly, not just the adjacent one.

![nopCommerce onion architecture (current state, source: upstream nopCommerce/docs)](./images/nopCommerceArchitecture.png)

The solution is organised under `src/` into `Libraries/` (Core, Data, Services), `Presentation/` (Nop.Web, Nop.Web.Framework), `Plugins/` (source — built DLLs deploy into `Presentation/Nop.Web/Plugins/`), and `Tests/`. Dependency rules are enforced through project references in the `.csproj` files:

| Project | Depends on | Responsibility |
|---|---|---|
| **Nop.Core** | (none) | Domain entities, caching abstractions, event contracts |
| **Nop.Data** | Nop.Core | Data access via linq2db + FluentMigrator (SQL Server, MySQL, PostgreSQL) |
| **Nop.Services** | Nop.Core, Nop.Data | Business logic: orders, tax, shipping, catalog, scheduled tasks |
| **Nop.Web.Framework** | Nop.Core, Nop.Data, Nop.Services | Presentation infra: validation, bundling, middleware pipeline |
| **Nop.Web** | all of the above | ASP.NET Core MVC: public store + admin area |
| **Plugins** | Nop.Web or Nop.Web.Framework | Independent extensions with their own data access, controllers, and views |

The core layers share a single relational database with no hard service boundaries, and the entire platform runs as a single ASP.NET Core process.

## Multi-Store Model

nopCommerce has a built-in multi-store concept (`Domain/Stores/Store.cs`). Each store has its own URL, company metadata, theme, and settings. However, the model is **opt-in isolation**:

- Products, categories, and manufacturers use a generic `StoreMapping` bridge table (`EntityId`, `EntityName`, `StoreId`) — only applied when `LimitedToStores = true`
- Without explicit mappings, all products appear in all stores by default
- Settings can be overridden per store (`Setting.StoreId = 0` is global fallback; `> 0` is store-specific)

There is no concept of a **store group**, store hierarchy, or parent-child store relationship.

## What nopCommerce Supports Today (Seams)

| Capability | Mechanism | Maturity |
|---|---|---|
| Store-specific settings | `Setting.StoreId` with global fallback | Solid — fully implemented |
| Store-scoped orders | `Order.StoreId` field, filtered queries | Solid — enforced at creation |
| Store-scoped shopping cart | `ShoppingCartItem.StoreId` + `CartsSharedBetweenStores` setting | Solid (when setting is false) |
| Per-store tier pricing | `TierPrice.StoreId` (0 = all) | Partial — opt-in |
| Store-limited catalog | `StoreMapping` bridge (opt-in) | Partial — not mandatory |
| Per-store theme/branding | Theme settings per store | Solid |

## Pressure Points for Scenario A

The following are the architectural conflicts identified in the codebase that directly affect the federated scenario:

### P1 — Product base price is global
`Product.Price` (`Domain/Catalog/Product.cs`) is a single decimal field. It has no store dimension. Per-store pricing requires the `TierPrice` mechanism, which is opt-in complexity that must be explicitly configured per product per store.

**Impact:** BUs cannot independently own their pricing logic without either (a) maintaining a parallel tier price for every product, or (b) introducing an external pricing service.

### P2 — Customer identity is fully global
`Customer.Email` and `Customer.Username` are global with no database-level uniqueness constraint (`CustomerBuilder.cs` maps both as `.AsString(1000).Nullable()` with no `.Unique()`). Uniqueness is enforced only at application level via `GetCustomerByEmailAsync` / `GetCustomerByUsernameAsync`, both of which query without any `StoreId` filter.

`RegisteredInStoreId` is set at registration time (`Nop.Web/Controllers/CustomerController.cs:804` for storefront sign-ups, `Nop.Web/Areas/Admin/Controllers/CustomerController.cs:354` for admin-created customers). It is used in two non-access-control contexts: filtering customers for incomplete registration follow-up emails (`ProcessIncompleteRegistrationsTask.cs:85`) and routing notification emails to the correct store templates (`WorkflowMessageService.cs:2825`). It is **never used to restrict a customer's access to any store** — no middleware, policy, or checkout query filters by `RegisteredInStoreId`.

`CustomerRole` has no `StoreId` field. Roles like "Wholesale Buyer" or "VIP Member" are group-wide, not BU-specific.

**Impact:** BUs cannot have private customer bases, BU-specific roles, or different loyalty rules. A customer registered in BU1 has implicit access to BU2. The absence of a DB-level uniqueness constraint also means duplicate emails across stores are possible via direct DB access or race conditions.

### P3 — Inventory is warehouse-centric, not BU-aware
`ProductWarehouseInventory` links products to warehouses. Warehouses have no `StoreId` field. All stores draw from the same warehouse pool.

**Impact:** BUs cannot maintain independent inventory assumptions or stock allocation. A stock depletion in BU1 is a stock depletion everywhere.

### P4 — No cross-process coordination mechanism
nopCommerce does have an in-process event system: `IEventPublisher` (defined in Nop.Core) with `IConsumer<T>` handlers (in Nop.Services), plus automatic `EntityInsertedEvent<T>` / `EntityUpdatedEvent<T>` / `EntityDeletedEvent<T>` fired by `EntityRepository<T>` on every CRUD operation. However, this system is unsuitable for federation:

- **In-process only** — events do not cross process or BU boundaries; there is no broker
- **Sequential dispatch** — consumers are awaited one after another; a slow consumer blocks the publisher
- **No durability** — if a consumer is unavailable, the event is lost (errors are caught and logged, but not retried or persisted)

**Impact:** Any federated behaviour across BUs (shared customer profiles, catalog sync, event-driven consistency) requires external messaging infrastructure. The existing event abstraction can serve as a publish point, but the transport must be replaced or augmented with a durable broker.

### P5 — Settings eventual consistency
When `StoreId = 0` (global) settings are updated, all stores are affected immediately with no coordination or approval step. There is no per-BU setting ownership or governance.

**Impact:** A group-level admin change can affect all BUs simultaneously with no isolation.

### P6 — `IgnoreStoreLimitations` is a global bypass
`CatalogSettings.IgnoreStoreLimitations` is a boolean setting. When `true`, `ApplyStoreMapping` short-circuits immediately (`StoreMappingService.cs:95`) and returns the full unfiltered query regardless of any `LimitedToStores` flags or `StoreMapping` records. All catalog isolation is silently disabled.

**Impact:** A single admin toggle disables all BU-level product isolation with no warning. This is a latent architectural risk for any federated deployment.

### P7 — ACL is role-scoped only, not store-scoped
`AclRecord` restricts product/category visibility by `CustomerRoleId`. There is no store-aware ACL. A product visible to role "Wholesale" is visible in all stores where that role exists.

**Impact:** BU-specific product access control requires workarounds (per-BU roles + StoreMapping), not a clean mechanism.

## Summary: What Remains in the Monolith and What Needs to Change

| Area | Current State | Required Evolution |
|---|---|---|
| Settings | Per-store capable, solid | Keep inside monolith; used for BU configuration |
| Orders | Store-scoped at creation | Keep; add BU-specific workflow hooks |
| Product catalog | Globally shared, opt-in isolation | Enforce mandatory StoreMapping; or introduce external PIM |
| Pricing | Global base + optional tier prices | Extend with BU pricing service or enforce tier prices |
| Inventory | Warehouse-global | Add BU-warehouse association; or delegate to BU-local ERP |
| Customer identity | Fully global | Federate via external IdP (Keycloak); keep local reference |
| Customer roles | Global only | Add BU-scoped roles; or keep global with strict naming convention |
| Cross-BU coordination | None | Introduce message broker (RabbitMQ / Kafka) |
