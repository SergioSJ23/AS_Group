#!/usr/bin/env bash
# Phase 1 / ADR-001 verification.
# Proves that bringing down db_bu1 does not affect BU2's homepage.
# Fires requests in background with a long timeout so nopCommerce has time
# to return HTTP 500 (DB connection timeout ~30s) — making the error visible
# in Prometheus and Grafana.
#
# Prerequisites: all containers must already be healthy (docker compose up -d).
# Usage: ./scripts/test-isolation.sh
set -euo pipefail

BU1_URL="${BU1_URL:-http://localhost:8081}"
BU2_URL="${BU2_URL:-http://localhost:8082}"
DOWN_SECONDS="${DOWN_SECONDS:-60}"

ts() { date +'%H:%M:%S'; }

cleanup() {
    echo ""
    echo "[$(ts)] ==> Restoring db_bu1..."
    docker compose start db_bu1
    echo "[$(ts)] ==> db_bu1 restarted. Waiting 15s for BU1 to recover..."
    sleep 15
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "${BU1_URL}/" 2>/dev/null || echo "000")
    echo "[$(ts)] ==> BU1 after recovery: HTTP ${STATUS}"
}
trap cleanup EXIT

echo "[$(ts)] ==> Generating baseline traffic on both BUs (10s)..."
for i in $(seq 1 10); do
    curl -s -o /dev/null --max-time 5 "${BU1_URL}/" &
    curl -s -o /dev/null --max-time 5 "${BU2_URL}/" &
    sleep 1
done
wait

echo "[$(ts)] ==> Stopping db_bu1..."
docker compose stop db_bu1
echo "[$(ts)] ==> db_bu1 is DOWN for ${DOWN_SECONDS}s."
echo "[$(ts)]    >> Grafana: http://localhost:3000 → 'Northstar — ADR Evidence' → ADR-001"
echo ""

# Fire BU1 requests in background with long timeout (need ~30s for 500 to arrive)
# These run in the background and complete on their own
echo "[$(ts)] ==> Launching BU1 background requests (60s timeout — waiting for 500 responses)..."
for i in $(seq 1 10); do
    curl -s -o /dev/null -w "[$(ts)] BU1 background request ${i}: HTTP %{http_code}\n" \
        --max-time 60 "${BU1_URL}/" &
    sleep 2
done

# Meanwhile poll BU2 every 2s to prove it stays up
BU2_OK=0; BU2_FAIL=0
END=$(( $(date +%s) + DOWN_SECONDS ))

echo "[$(ts)] ==> Polling BU2 every 2s to prove isolation..."
while [ "$(date +%s)" -lt "$END" ]; do
    S2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${BU2_URL}/" 2>/dev/null || echo "000")
    if [ "$S2" = "200" ]; then BU2_OK=$((BU2_OK+1)); else BU2_FAIL=$((BU2_FAIL+1)); fi
    echo "[$(ts)] BU2=${S2} (ok=${BU2_OK} fail=${BU2_FAIL})"
    sleep 2
done

wait  # wait for all background BU1 requests to complete

echo ""
echo "[$(ts)] ==> RESULT:"
echo "         BU2 (isolated): ${BU2_OK} ok, ${BU2_FAIL} fail"

if [ "${BU2_FAIL}" -eq 0 ]; then
    echo "[$(ts)] PASS: BU2 was 100% available throughout the BU1 DB outage."
else
    echo "[$(ts)] FAIL: BU2 had ${BU2_FAIL} failures — check output above."
fi
