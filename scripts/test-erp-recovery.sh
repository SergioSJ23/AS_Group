#!/usr/bin/env bash
set -euo pipefail

ERP_BU2="http://localhost:9002"
CIRCUIT_COOLDOWN=32

echo "=== ADR-004 Circuit Breaker — Recovery Demo ==="
echo

echo "1. Recovering BU2 ERP..."
curl -sf -X POST "$ERP_BU2/admin/recover" | python3 -m json.tool

echo
echo "2. BU2 ERP is now responding normally..."
curl -sf "$ERP_BU2/stock/DEMO-SKU-001" | python3 -m json.tool

echo
echo "3. Waiting ${CIRCUIT_COOLDOWN}s for circuit breaker cooldown to expire..."
echo "   (OPEN → HALF-OPEN after 30s, then probe triggers CLOSED)"
for i in $(seq 1 $CIRCUIT_COOLDOWN); do
  printf "\r   %d/%ds elapsed..." "$i" "$CIRCUIT_COOLDOWN"
  sleep 1
done
echo

echo
echo "4. Circuit is now HALF-OPEN. Next nopCommerce request will probe ERP."
echo "   Probe succeeds → circuit transitions to CLOSED."
echo
echo "5. After recovery:"
echo "   → 'Stock to be confirmed' banner disappears"
echo "   → Live stock quantity shown from ERP"
echo "   → Normal operation resumed automatically"
echo
echo "   Manual check: open http://localhost:8082 → navigate to any product with a SKU"
echo "   The yellow stale banner should be gone"
echo
echo "=== Recovery demo complete ==="
