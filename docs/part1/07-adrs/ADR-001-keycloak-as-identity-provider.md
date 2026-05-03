# ADR-001 - Federate identity via Keycloak as external IdP

**Status:** Proposed
**Date:** 2026-05-03
**Driver:** QA3 (Federated Identity), supports QA1
**Closes pressure point:** P2 (customer identity fully global, no BU-scoped roles)
**Bounded context:** BC1 - Group Identity
**ADD iteration:** 1

## Context

nopCommerce currently owns customer identity itself. `Customer.Email` and `Customer.Username` are global with no DB-level uniqueness constraint (`CustomerBuilder.cs:25-26`), `RegisteredInStoreId` is set at registration but never used for access control, and `CustomerRole` has no `StoreId` field. There is no mechanism for one customer to be recognised across two BUs without re-registration, and BU-specific roles (Wholesale, VIP, B2B) cannot be expressed cleanly because role scope is global.

The federation scenario requires a **single identity** the group owns, plus **BU-local role assignment** that does not bleed across BUs. The existing `IExternalAuthenticationMethod` plugin slot (already used by `Nop.Plugin.ExternalAuth.Facebook`) is a clean integration point.

## Decision

Adopt **Keycloak** as the group's external identity provider. Each nopCommerce BU instance becomes an OIDC relying party via a new `Nop.Plugin.ExternalAuth.Keycloak` plugin that implements `IExternalAuthenticationMethod`. Group-level roles travel as JWT claims; BU-local roles continue to live inside each nopCommerce instance and are mapped from token claims on first login per BU.

- Authentication flow: Authorization Code with PKCE
- Token lifetime: 5-minute access token, 30-minute refresh token, sliding session
- Group claims: `groups: ["Registered", "VerifiedEmail"]` (group-wide)
- BU role assignment: derived per BU from `groups` + BU-specific mapping rules; persisted as `CustomerCustomerRoleMapping` records local to that BU

## Consequences

**Positive.**
- Single sign-on across BUs satisfies QA3 directly.
- Identity is no longer a per-BU concern - adding a third BU costs only an OIDC client config in Keycloak.
- The DB-level uniqueness gap on `Customer.Email` becomes a non-issue: identity uniqueness is enforced upstream by Keycloak.
- Existing nopCommerce `Customer` records remain - they become local profiles linked by Keycloak `sub` claim.

**Negative.**
- Identity becomes a group-level dependency. Keycloak unavailability blocks login on every BU. Mitigated by an HA pair (active/passive) and by the cookie-based session continuing to work for already-logged-in users until token expiry.
- A migration is required for existing customers - link by email on first post-migration login, with an admin tool for manual reconciliation.
- The login UX changes: customers are redirected to Keycloak. Acceptable per the federation business case.

**Trade-off accepted.** Convenience-of-self-contained-auth is traded for federation. The trade-off is intentional and aligns with the scenario.

## Rejected Alternatives

### A. Keep nopCommerce as the identity owner, sync customers via events
*Rejected.* Eventual consistency on identity creates correctness problems: if BU2 has not yet received the "customer created in BU1" event, the customer cannot log in. Identity is exactly the wrong place for eventual consistency.

### B. Use Azure AD B2C / Auth0 / Cognito instead of Keycloak
*Rejected for the assignment, but architecturally equivalent.* Keycloak is open-source, self-hostable, and free of vendor lock-in - preferred for a teaching demo. The plug-in seam is identical: any OIDC-compliant IdP fits. The decision is "**OIDC-based external IdP**"; Keycloak is the chosen instance.

### C. Build a custom shared-identity service inside the group platform
*Rejected.* Reinvents OIDC. Cost-to-build vs Keycloak is unjustifiable, and the resulting service would be a worse Keycloak.

### D. SAML instead of OIDC
*Rejected.* SAML is XML-heavy and awkward for SPA / mobile flows. OIDC + JWT covers the storefront, the admin area, and any future mobile clients with one protocol.

## Traceability

| Trace | Reference |
|---|---|
| Driver | doc 04 - QA3 (Federated Identity) |
| Pressure point closed | doc 02 - P2 |
| Bounded context | doc 03 - BC1 |
| ADD iteration | doc 06 - Iteration 1 |
| Plugin seam | `Nop.Services/Authentication/External/IExternalAuthenticationMethod.cs` |
