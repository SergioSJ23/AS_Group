#!/usr/bin/env bash
# Demo: ADR-005 search fallback under load.
# Runs k6 search-load in the background. ~40s in, pauses Meilisearch so every
# query throws and nopCommerce takes the DB fallback path. After ~50s, unpauses
# Meilisearch and the meili backend recovers. Total run ~3 minutes.
#
# Watch on the Grafana dashboard (row "ADR-005"):
#   * "Search duration by backend" — meili line goes flat, error line appears
#   * "Fallback rate"              — climbs from 0 to ~tens/s
#   * k6 row                        — http_req_failed stays under threshold
set -euo pipefail

ts() { date +'%H:%M:%S'; }
banner() { echo; echo "[$(ts)] ───── $* ─────"; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

banner "Starting k6 search-load in background (~150s run)"
./scripts/run-loadtest.sh search-load >/tmp/k6-search-fallback.log 2>&1 &
K6_PID=$!
trap '
  if kill -0 "$K6_PID" 2>/dev/null; then kill "$K6_PID" 2>/dev/null || true; fi
  docker unpause northstar-meilisearch-1 2>/dev/null || true
' EXIT

echo "  k6 pid=$K6_PID, log=/tmp/k6-search-fallback.log"
echo "  Open http://localhost:3000/d/northstar-adr-evidence now."

sleep 40
banner "Pausing Meilisearch — fallback path should activate"
docker pause northstar-meilisearch-1

sleep 50
banner "Unpausing Meilisearch — meili backend should resume"
docker unpause northstar-meilisearch-1

banner "Waiting for k6 to finish (will exit on its own)"
wait "$K6_PID" || true

banner "Done. Grafana row 'ADR-005' should show the meili→error→meili transition."
echo "  k6 log: tail -50 /tmp/k6-search-fallback.log"
