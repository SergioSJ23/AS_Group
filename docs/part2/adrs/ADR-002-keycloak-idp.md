# ADR-002: Federate Identity via Keycloak as External IdP

**Status:** Accepted  
**Driver:** QA3 (Federated Identity — Security / Interoperability); supports QA1  
**Pressure point:** P2 (customer identity is fully global)  
**Bounded context:** BC1 (Group Identity)  
**ADD iteration:** 2

---

## Context

nopCommerce currently owns customer identity, but its identity model is the wrong shape
for a federated group: customer email and username are global with no DB-level uniqueness
per store, customer roles have no store dimension, and there is no mechanism for one
customer to be recognised across two BUs without re-registering. With per-BU databases
(ADR-001), identity is the one piece of cross-BU shared state that must stay in lock-step.
A within-instance solution cannot work. The existing `IExternalAuthenticationMethod` plug-in
slot offers a clean integration point that does not require touching the core.

---

## Decision

The group adopts Keycloak as its external Identity Provider. Each nopCommerce BU instance
becomes an OIDC relying party through a custom Keycloak plugin implementing
`IExternalAuthenticationMethod`. Group-level roles travel inside JWT claims while BU-local
roles continue to live inside each nopCommerce instance, mapped from token claims on first
login per BU. The authentication flow is Authorization Code with PKCE (`response_mode=query`
to avoid SameSite cookie failure on cross-site POST redirects).

---

## Consequences

QA3 is satisfied directly. The email-uniqueness gap becomes Keycloak's problem, and
existing customer records survive as local profiles linked by Keycloak subject claim.
Identity becomes a group-level dependency: when Keycloak is unavailable, no new logins are
possible. Mitigated by short-lived tokens with refresh and a Keycloak HA pair.

**Accepted cost:** Login now depends on Keycloak availability. Existing customers must be
migrated by email match on first SSO login.

---

## Implementation (Part 2)

Plugin: `src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/`

Key implementation details:
- `IExternalAuthenticationMethod` + `AddOpenIdConnect` registered via `AuthenticationBuilder`
- `response_mode=query` (not default `form_post`) — prevents SameSite=Lax cookie failure on cross-origin redirect
- On callback: find-or-create `Customer` row keyed by Keycloak `sub` claim; map JWT `groups` claim to BU-local role IDs prefixed with BU name
- Two OIDC clients in realm `northstar`: `bu1-nopcommerce` (redirects `:8081`) and `bu2-nopcommerce` (redirects `:8082`)

**Keycloak realm:** `spike/keycloak/realm-northstar.json`

**Verification (2026-05-31):**
```
BU1 GET /keycloakauthentication/login
→ HTTP 302 Location: keycloak.../auth?client_id=bu1-nopcommerce&...

BU2 GET /keycloakauthentication/login
→ HTTP 302 Location: keycloak.../auth?client_id=bu2-nopcommerce&...

Both redirect to same realm "northstar". Silent re-auth on BU2 reuses
Keycloak session from BU1 login (no credential re-prompt).
```

---

## Rejected Alternatives

**Keep nopCommerce as identity owner and replicate customers between BUs through events:**
rejected because identity is the one domain where eventual consistency turns latency into
a correctness bug — a customer who cannot log in because their replication event has not
yet propagated is locked out, not merely slowed down.

**Azure AD B2C / Auth0 / Cognito:** match Keycloak architecturally but vendor lock-in and
recurring cost are unwarranted when the integration seam is identical for any OIDC IdP.

**Bespoke group-level identity service:** amounts to a from-scratch rebuild of OIDC;
discarded on cost alone.

**SAML:** XML payloads sit awkwardly with SPA and future mobile flows; OIDC plus JWT is
the cleaner long-term protocol.
