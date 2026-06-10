# Northstar load tests (k6)

Three scenarios that drive the storefronts so the resilience claims in ADR-003,
ADR-004 and ADR-005 can be *observed* in Grafana, not just argued.

## Prereqs

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
```

Prometheus at <http://localhost:9090>, Grafana at <http://localhost:3000>
(dashboard: *Northstar — ADR Evidence*).

## Scenarios

| Script | Proves | Operator action mid-run |
|---|---|---|
| `search-load.js` | ADR-005 fallback | `docker pause meilisearch` (then `docker unpause`) |
| `checkout-load.js` | ADR-003 outbox durability | `docker pause espocrm_consumer` (then `docker unpause`) |
| `product-detail-load.js` | ADR-004 ERP breaker | `./scripts/test-erp-failure.sh` then `./scripts/test-erp-recovery.sh` |

## Run

```bash
./scripts/run-loadtest.sh search-load
./scripts/run-loadtest.sh checkout-load
./scripts/run-loadtest.sh product-detail-load
```

Each run takes ~2-3 minutes. Metrics stream into Prometheus via remote-write and
appear on the *k6 load* row of the dashboard, alongside the matching ADR row.

## Notes

- Scripts run inside the `northstar_default` docker network so they hit the
  storefronts at `http://nop_bu1` / `http://nop_bu2` (port 80, internal).
- Override the network with `K6_NETWORK=<name> ./scripts/run-loadtest.sh ...`
  if compose was started under a different project name.
- Product slugs are pinned to the seed data (`scripts/seed-bu{1,2}.sql`). If you
  reseed with different slugs, update `loadtests/lib/config.js`.
