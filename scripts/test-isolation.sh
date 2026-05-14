#!/usr/bin/env bash
# Phase 1 / ADR-001 verification.
# Proves that bringing down db_bu1 does not affect BU2's homepage.
#
# Prerequisites: all containers must already be healthy (docker compose up -d).
# Usage: ./scripts/test-isolation.sh
set -euo pipefail

BU2_URL="${BU2_URL:-http://localhost:8082}"

cleanup() {
    echo "==> Restoring db_bu1..."
    docker compose start db_bu1
    echo "==> db_bu1 restarted."
}
trap cleanup EXIT

echo "==> Stopping db_bu1..."
docker compose stop db_bu1

echo "==> Waiting 5s for in-flight connections to drain..."
sleep 5

echo "==> GET ${BU2_URL}/ ..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "${BU2_URL}/")

if [ "${STATUS}" -eq 200 ]; then
    echo "PASS: BU2 returned HTTP ${STATUS} while db_bu1 was down."
    exit 0
else
    echo "FAIL: BU2 returned HTTP ${STATUS} — expected 200."
    exit 1
fi
