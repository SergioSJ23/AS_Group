#!/usr/bin/env bash
set -euo pipefail

ERP_BU1="http://localhost:9001"
ERP_BU2="http://localhost:9002"
BU2_URL="http://localhost:8082"
TEST_SKU="DEMO-SKU-001"

echo "=== ADR-004 Circuit Breaker — Failure Demo ==="
echo

echo "1. Verifying both ERPs healthy..."
curl -sf "$ERP_BU1/health" | python3 -m json.tool
curl -sf "$ERP_BU2/health" | python3 -m json.tool

echo
echo "2. Live stock from BU2 ERP (circuit CLOSED)..."
curl -sf "$ERP_BU2/stock/$TEST_SKU" | python3 -m json.tool

echo
echo "3. Breaking BU2 ERP..."
curl -sf -X POST "$ERP_BU2/admin/break" | python3 -m json.tool

echo
echo "4. Verifying BU2 ERP returns 503..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ERP_BU2/stock/$TEST_SKU")
echo "   BU2 ERP /stock status: $STATUS"
if [ "$STATUS" != "503" ]; then
  echo "ERROR: expected 503, got $STATUS" >&2; exit 1
fi

echo
echo "5. BU1 ERP still healthy (isolation check)..."
STATUS_BU1=$(curl -s -o /dev/null -w "%{http_code}" "$ERP_BU1/stock/$TEST_SKU")
echo "   BU1 ERP /stock status: $STATUS_BU1"
if [ "$STATUS_BU1" != "200" ]; then
  echo "ERROR: BU1 ERP should be unaffected, got $STATUS_BU1" >&2; exit 1
fi
echo "   BU1 is unaffected ✓"

echo
echo "6. Triggering circuit breaker in nopCommerce BU2 (need 5 failures)..."
echo "   Requesting BU2 product pages to accumulate failures..."
for i in $(seq 1 6); do
  curl -sf "$BU2_URL/" -o /dev/null -w "   Request $i: HTTP %{http_code}\n" || true
done

echo
echo "7. After 5+ ERP failures, subsequent product page requests will show:"
echo "   → 'Stock to be confirmed' stale banner (circuit OPEN, cached data served)"
echo "   → BU2 storefront remains fully operational"
echo "   → BU1 storefront is completely unaffected"
echo
echo "   Manual check: open http://localhost:8082 → navigate to any product with a SKU"
echo "   Look for the yellow 'Stock to be confirmed' banner"
echo
echo "=== Failure demo complete. Run test-erp-recovery.sh to restore. ==="
