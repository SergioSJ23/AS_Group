#!/usr/bin/env bash
# Demo: ADR-004 ERP circuit breaker under load.
# Runs k6 product-detail-load against BU1 in the background. ~40s in, breaks
# the BU1 ERP (POST /admin/break) so calls to /stock return 503. After 5
# consecutive failures the breaker flips CLOSED→OPEN; the storefront keeps
# serving 200 by reading the cached stock. ~80s later, recovers the ERP; the
# breaker probes HALF-OPEN → CLOSED on the next success.
#
# Watch on the Grafana dashboard (row "ADR-004"):
#   * "Breaker state"        — stat flips 0 (CLOSED) → 2 (OPEN) → 1 (HALF) → 0
#   * "Breaker transitions"  — spikes at break and recover
#   * "ERP call duration"    — outcome=live disappears, fallback-cache appears
set -euo pipefail

ts() { date +'%H:%M:%S'; }
banner() { echo; echo "[$(ts)] ───── $* ─────"; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

ERP_BU1="http://localhost:9001"

banner "Starting k6 product-detail-load in background (~180s run)"
./scripts/run-loadtest.sh product-detail-load >/tmp/k6-breaker.log 2>&1 &
K6_PID=$!
trap '
  if kill -0 "$K6_PID" 2>/dev/null; then kill "$K6_PID" 2>/dev/null || true; fi
  curl -sf -X POST "'$ERP_BU1'/admin/recover" >/dev/null || true
' EXIT

echo "  k6 pid=$K6_PID, log=/tmp/k6-breaker.log"
echo "  Open http://localhost:3000/d/northstar-adr-evidence now."

sleep 40
banner "Breaking erp_bu1 (POST /admin/break) — expect breaker to OPEN within 5 failed calls"
curl -sf -X POST "$ERP_BU1/admin/break" | python3 -m json.tool || true

sleep 80
banner "Recovering erp_bu1 (POST /admin/recover) — breaker should probe and close"
curl -sf -X POST "$ERP_BU1/admin/recover" | python3 -m json.tool || true

banner "Waiting for k6 to finish"
wait "$K6_PID" || true

banner "Done. Grafana row 'ADR-004' should show breaker 0→2→1→0."
echo "  k6 log: tail -50 /tmp/k6-breaker.log"
