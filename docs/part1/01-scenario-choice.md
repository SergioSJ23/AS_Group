# Scenario Choice — Federated Commerce After Acquisitions

## Selected Scenario: A

## Business Context

**Northstar Living Group** is a retail holding company that grew through acquisition. It now operates several specialist brands under one corporate umbrella — each with its own product catalog, pricing habits, inventory logic, and operational rhythm. The brands were built independently and reflect that: different product types, different customer bases, different fulfillment expectations.

Leadership wants a shared digital foundation to reduce platform cost and enable group-level insights, but cannot destroy the local autonomy that makes each brand work. Forcing a single rigid model would either homogenise what should not be homogenised, or introduce so much exception logic that the "shared" platform becomes more fragile than what it replaced.

## Why This Scenario Creates Real Architectural Pressure

The tension is not simply "how do we share code." It is a structural conflict between two legitimate requirements:

| Requirement | Direction |
|---|---|
| Group-level identity, single sign-on, shared customer base | Pull toward centralisation |
| BU-specific pricing, catalog rules, order workflows | Pull toward isolation |
| One platform, lower operational cost | Pull toward monolith |
| Independent deployability, no cross-BU failures | Pull toward separation |

This creates genuine architectural decisions with trade-offs. There is no neutral position: every choice about what to share and what to isolate has consequences for coupling, failure propagation, and autonomy.

## Why nopCommerce Makes This Interesting

nopCommerce is a **store-aware but not store-enforced** system. It has a multi-store model built in, but the isolation is opt-in. By default, products appear in all stores, customer identities are global, roles have no store scope, and inventory is warehouse-centric without BU assignment.

This means:
- The system already has the concept of stores and store-scoped settings
- But it lacks the enforcement, the boundary contracts, and the asynchronous coordination needed for real federation

The assignment is to decide what to enforce, what to extract, and what to leave shared — and to do so with explicit architectural justification.

## Strategic Goals (from the scenario)

1. Create a shared digital foundation across the group
2. Preserve meaningful local autonomy for each business unit
3. Allow the platform to evolve without cross-unit instability and uncontrolled coupling
