# Chosen Framework — ADD (Attribute-Driven Design)

## Selected Framework: ADD 3.0

We apply **ADD (Attribute-Driven Design)** as the primary software architecture design framework for this evolution.

---

## What ADD Is

ADD is an iterative decomposition method where architectural decisions are driven by quality attribute scenarios and architectural drivers, not by feature lists or technology preferences.

The core loop is:

```
1. Select an element to decompose (start with the whole system)
2. Identify the architectural drivers (QA scenarios, constraints, concerns)
3. Choose an architectural pattern or tactic that responds to those drivers
4. Instantiate the pattern and allocate responsibilities
5. Define interfaces and interactions
6. Verify the decision satisfies the drivers
7. Repeat for sub-elements
```

---

## Why ADD Fits This Case

### 1. We have explicit quality attribute scenarios

The assignment requires "3 to 5 quality attribute scenarios that drive the design." ADD is built around exactly this input. Each QA scenario (QA1–QA5) maps directly to an ADD design round:

| QA Scenario | ADD Round | Decision Driven |
|---|---|---|
| QA1 — Fault Isolation | Round 1 | Extract BU-local ERP integration; introduce circuit breaker |
| QA2 — BU Pricing Autonomy | Round 2 | Enforce StoreMapping; BU-local tier price ownership |
| QA3 — Federated Identity | Round 3 | External IdP (Keycloak); nopCommerce as relying party |
| QA4 — Search Degradation | Round 4 | Fallback strategy; async re-index on recovery |
| QA5 — Cross-BU Consistency | Round 5 | Async event publication; idempotent CRM consumer |

### 2. We are evolving an existing system, not designing from scratch

ADD supports both greenfield and brownfield evolution. The current-state analysis (doc 02) establishes the baseline. Each ADD round decides what to enforce, extract, or leave unchanged — which is exactly the selective evolution this scenario requires.

ADD explicitly asks: "what is already there, what constraints exist, and what must change to satisfy the drivers?" This is a better fit than frameworks that assume a blank slate.

### 3. Traceability is built into the method

ADD produces a direct trace from driver → decision → implementation. The assignment evaluation criterion "traceability from drivers to implementation" is satisfied naturally by the ADD output. Each ADR in doc 06 will reference the QA scenario that triggered it.

### 4. The scope is focused

The assignment warns against "inflated designs that are only convincing in diagrams." ADD's decomposition is bounded by the selected architectural drivers — you stop when the drivers are satisfied, not when you run out of technologies to add. This aligns with the principle of selective architectural change.

---

## Why Not ACDM or ADM/TOGAF

### ACDM (Architecture Centric Design Method)
ACDM is more comprehensive and includes explicit stakeholder negotiation, concept generation, and architectural evaluation phases. It is well-suited for large new systems with multiple competing stakeholder views. For this assignment — evolving one platform for one holding group with well-defined drivers — ACDM adds overhead without proportional benefit. The stakeholder negotiation and multiple-concept generation phases are not warranted at this scope.

### ADM / TOGAF
TOGAF's ADM is an enterprise architecture framework covering business, data, application, and technology layers across an entire organisation. It is appropriate when the scope is the full enterprise IT landscape and involves multiple programmes. For a focused evolution of a single commerce platform with 5 QA drivers, TOGAF introduces governance overhead (architecture repository, compliance assessment, migration planning at enterprise scale) that is disproportionate to the problem.

---

## How ADD Is Applied in This Project

| ADD Step | Where it appears |
|---|---|
| Identify architectural drivers | Doc 04 (QA scenarios) + Doc 02 (pressure points) |
| Choose patterns and tactics | Doc 06 (ADRs) — one ADR per major decision |
| Allocate responsibilities | Doc 03 (bounded contexts and ownership table) |
| Define interactions | Doc 06 ADRs + target architecture diagram |
| Verify against drivers | Evidence pack (Part 2) — runtime tests against QA measures |
