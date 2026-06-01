#!/usr/bin/env bash
# Demo: shared customer profile across federated units (Scenario A — UC "shared
# customer operations").
#
# Publishes one order from BU1 and one from BU2 for the SAME customer (same email)
# to the northstar.events exchange, then reads the resulting EspoCRM contact to show
# that BOTH purchases land on a single unified profile — proving the cross-BU customer
# view without either BU touching the other's database (ADR-001 + ADR-003).
#
# Usage: ./scripts/demo-cross-bu-crm.sh

set -euo pipefail

RABBITMQ_MGMT="${RABBITMQ_MGMT:-http://localhost:15672}"
ESPOCRM_URL="${ESPOCRM_URL:-http://localhost:8083}"
RABBITMQ_USER="${RABBITMQ_USER:-northstar}"
RABBITMQ_PASS="${RABBITMQ_PASS:-northstar}"
ESPOCRM_USER="${ESPOCRM_USER:-admin}"
ESPOCRM_PASS="${ESPOCRM_PASS:-admin}"
TIMEOUT=35

ts() { date +'%H:%M:%S'; }
banner() { echo; echo "[$(ts)] ───── $* ─────"; }

# One customer, shared across both business units (same email — as it would be
# under Keycloak SSO, where the email comes from the same identity claim).
CUSTOMER_EMAIL="alice-${RANDOM}@northstar.test"
CUSTOMER_ID=$((RANDOM + 50000))

publish_order() {
  local bu_id="$1" order_id="$2" total="$3"
  local payload
  payload=$(printf '{"orderId":%d,"orderGuid":"00000000-0000-0000-0000-000000000001","customerId":%d,"customerEmail":"%s","orderTotal":%s,"buId":"%s","timestamp":"%s"}' \
    "$order_id" "$CUSTOMER_ID" "$CUSTOMER_EMAIL" "$total" "$bu_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")

  local result routed
  result=$(curl -s -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
    -X POST "${RABBITMQ_MGMT}/api/exchanges/%2F/northstar.events/publish" \
    -H "content-type: application/json" \
    -d "{
      \"properties\": {\"delivery_mode\": 2},
      \"routing_key\": \"${bu_id}.order.placed\",
      \"payload\": $(echo "$payload" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
      \"payload_encoding\": \"string\"
    }")
  routed=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('routed', False))" 2>/dev/null || echo "false")
  if [[ "$routed" == "True" || "$routed" == "true" ]]; then
    echo "  OK — ${bu_id} order #${order_id} (€${total}) published and routed"
  else
    echo "  WARN — ${bu_id} order not routed: $result"
  fi
}

echo "=== Shared cross-BU customer profile demo ==="
echo "Customer: ${CUSTOMER_EMAIL}  (same identity in both BUs)"

# ── 1. One purchase in each business unit ────────────────────────────────────
banner "Customer buys in BU1 (HomeStyle), then in BU2 (WorkSpace)"
publish_order "bu1" "$((RANDOM + 90000))" "149.99"
sleep 3
publish_order "bu2" "$((RANDOM + 90000))" "299.00"

# ── 2. Wait for both to land on the shared contact ───────────────────────────
banner "Waiting for the espocrm_consumer to fold both orders into one contact"
ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$CUSTOMER_EMAIL")
DESC=""
for i in $(seq 1 "$TIMEOUT"); do
  RESPONSE=$(curl -s -u "${ESPOCRM_USER}:${ESPOCRM_PASS}" \
    "${ESPOCRM_URL}/api/v1/Contact?where%5B0%5D%5Btype%5D=equals&where%5B0%5D%5Bfield%5D=emailAddress&where%5B0%5D%5Bvalue%5D=${ENCODED}" \
    2>/dev/null || echo '{"total":0,"list":[]}')
  DESC=$(echo "$RESPONSE" | python3 -c "
import sys,json
d=json.load(sys.stdin)
if d.get('total',0) >= 1:
    print(d['list'][0].get('description') or '')
" 2>/dev/null || echo "")
  # Both BU lines present?
  if echo "$DESC" | grep -q '\[bu1\]' && echo "$DESC" | grep -q '\[bu2\]'; then
    break
  fi
  printf "  [%2ds] waiting for both BU orders to appear...\r" "$i"
  sleep 1
done
echo ""

# ── 3. Show the unified profile ──────────────────────────────────────────────
banner "Unified customer profile in EspoCRM"
curl -s -u "${ESPOCRM_USER}:${ESPOCRM_PASS}" \
  "${ESPOCRM_URL}/api/v1/Contact?where%5B0%5D%5Btype%5D=equals&where%5B0%5D%5Bfield%5D=emailAddress&where%5B0%5D%5Bvalue%5D=${ENCODED}" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f\"  contacts matching this email : {d['total']}  (expected 1 — one customer, not one-per-BU)\")
if d.get('list'):
    c=d['list'][0]
    print(f\"  name                         : {c.get('firstName')} {c.get('lastName')}\")
    print(f\"  email                        : {c.get('emailAddress')}\")
    print( '  cross-BU purchase history    :')
    for line in (c.get('description') or '').split(chr(10)):
        if line.strip():
            print(f'      {line}')
"

# ── 4. Verdict ───────────────────────────────────────────────────────────────
banner "Result"
if echo "$DESC" | grep -q '\[bu1\]' && echo "$DESC" | grep -q '\[bu2\]'; then
  echo "  PASS: orders from BU1 and BU2 both visible on ONE shared customer profile."
  echo "        No BU read the other's database — the unified view is built only from"
  echo "        the order events each BU published (ADR-001 boundary preserved)."
else
  echo "  FAIL: did not find both [bu1] and [bu2] orders on the contact within ${TIMEOUT}s."
  echo "        Check: docker compose logs espocrm_consumer"
  exit 1
fi
