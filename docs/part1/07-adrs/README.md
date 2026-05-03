# Architecture Decision Records

Each ADR records one architectural decision in [Michael Nygard's format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions): Status, Context, Decision, Consequences, plus a Rejected Alternatives section as required by the assignment brief.

| ID | Title | Status | Driver |
|---|---|---|---|
| [ADR-001](./ADR-001-keycloak-as-identity-provider.md) | Federate identity via Keycloak as external IdP | Proposed | QA3 |
| [ADR-002](./ADR-002-rabbitmq-event-bus.md) | Bridge `IEventPublisher` to RabbitMQ for cross-BU events | Proposed | QA5 |
| [ADR-003](./ADR-003-bu-local-erp-circuit-breaker.md) | BU-local ERP behind anti-corruption layer with circuit breaker | Proposed | QA1 |
| [ADR-004](./ADR-004-meilisearch-with-db-fallback.md) | Federated Meilisearch with DB fallback strategy | Proposed | QA4 |
| [ADR-005](./ADR-005-mandatory-storemapping.md) | Mandatory `StoreMapping` enforcement and BU-scoped pricing | Proposed | QA2 |

Each ADR traces back to:
- the QA scenario it satisfies (doc 04),
- the pressure point it closes from the current-state analysis (doc 02),
- the bounded context it operates in (doc 03),
- the ADD iteration that produced it (doc 06).
