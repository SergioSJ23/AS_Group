#!/usr/bin/env bash
# Run a k6 scenario inside the `northstar_default` docker network so that
# nop_bu1, nop_bu2 and prometheus all resolve by hostname. k6 ships metrics to
# Prometheus via the experimental remote-write output; the ADR-evidence Grafana
# dashboard plots them in real time.
#
# Usage:
#   ./scripts/run-loadtest.sh search-load
#   ./scripts/run-loadtest.sh checkout-load
#   ./scripts/run-loadtest.sh product-detail-load
#
# Prerequisites:
#   docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d
set -euo pipefail

scenario="${1:-}"
if [[ -z "$scenario" ]]; then
  echo "Usage: $0 <search-load|checkout-load|product-detail-load>" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script_path="loadtests/scenarios/${scenario}.js"

if [[ ! -f "$repo_root/$script_path" ]]; then
  echo "Scenario not found: $repo_root/$script_path" >&2
  exit 1
fi

network="${K6_NETWORK:-northstar_default}"
prom_url="${K6_PROMETHEUS_RW_SERVER_URL:-http://prometheus:9090/api/v1/write}"

echo "→ Running $scenario on network=$network, remote-write=$prom_url"

docker run --rm \
  --network "$network" \
  -v "$repo_root/loadtests:/scripts:ro" \
  -e K6_PROMETHEUS_RW_SERVER_URL="$prom_url" \
  -e K6_PROMETHEUS_RW_TREND_STATS="p(50),p(95),p(99),max" \
  grafana/k6:latest run \
  -o experimental-prometheus-rw \
  "/scripts/scenarios/${scenario}.js"
