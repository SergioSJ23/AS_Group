#!/usr/bin/env bash
# Phase 3 / ADR-003 verification.
#
# Publishes a synthetic order message directly to the northstar.events exchange via the
# RabbitMQ management API, then polls EspoCRM to confirm the espocrm_consumer processed it.
#
# Usage: ./scripts/test-outbox.sh
#
# Prerequisites: all containers healthy (docker compose up -d --build).
# The espocrm_consumer container must be running.

set -euo pipefail

RABBITMQ_MGMT="${RABBITMQ_MGMT:-http://localhost:15672}"
ESPOCRM_URL="${ESPOCRM_URL:-http://localhost:8083}"
RABBITMQ_USER="${RABBITMQ_USER:-northstar}"
RABBITMQ_PASS="${RABBITMQ_PASS:-northstar}"
ESPOCRM_USER="${ESPOCRM_USER:-admin}"
ESPOCRM_PASS="${ESPOCRM_PASS:-admin}"
TEST_EMAIL="outbox-test-$(date +%s)@northstar.test"
TEST_ORDER_ID=$((RANDOM + 90000))
TEST_CUSTOMER_ID=$((RANDOM + 50000))
BU_ID="bu2"
# QA5 response measure: CRM updated within 30s under normal conditions.
TIMEOUT=30

# ── 1. Verify espocrm_consumer is running ────────────────────────────────────
echo "==> 1. Checking espocrm_consumer container..."
CONSUMER_STATE=$(docker compose ps espocrm_consumer --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('State','') if isinstance(d,dict) else d[0].get('State',''))" 2>/dev/null || echo "unknown")
if [[ "$CONSUMER_STATE" != "running" ]]; then
    echo "WARN: espocrm_consumer state is '$CONSUMER_STATE' (expected running). Continuing anyway."
fi
echo "    espocrm_consumer: $CONSUMER_STATE"

# ── 2. Publish synthetic order via RabbitMQ management API ──────────────────
echo "==> 2. Publishing synthetic order to northstar.events (routing key: ${BU_ID}.order.placed)..."
PAYLOAD=$(printf '{"orderId":%d,"orderGuid":"00000000-0000-0000-0000-000000000001","customerId":%d,"customerEmail":"%s","orderTotal":149.99,"buId":"%s","timestamp":"%s"}' \
    "$TEST_ORDER_ID" "$TEST_CUSTOMER_ID" "$TEST_EMAIL" "$BU_ID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")

PUBLISH_RESULT=$(curl -s -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
    -X POST "${RABBITMQ_MGMT}/api/exchanges/%2F/northstar.events/publish" \
    -H "content-type: application/json" \
    -d "{
        \"properties\": {\"delivery_mode\": 2},
        \"routing_key\": \"${BU_ID}.order.placed\",
        \"payload\": $(echo "$PAYLOAD" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
        \"payload_encoding\": \"string\"
    }")
ROUTED=$(echo "$PUBLISH_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('routed', False))" 2>/dev/null || echo "false")
if [[ "$ROUTED" != "True" && "$ROUTED" != "true" ]]; then
    echo "WARN: RabbitMQ reports message was not routed (queue may be empty or binding missing)."
    echo "      Response: $PUBLISH_RESULT"
else
    echo "    OK — message published and routed"
fi

# ── 3. Wait for consumer to process ─────────────────────────────────────────
echo "==> 3. Waiting up to ${TIMEOUT}s for EspoCRM contact to appear..."
FOUND=false
ELAPSED=0
for i in $(seq 1 "$TIMEOUT"); do
    ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TEST_EMAIL")
    RESPONSE=$(curl -s -u "${ESPOCRM_USER}:${ESPOCRM_PASS}" \
        "${ESPOCRM_URL}/api/v1/Contact?where%5B0%5D%5Btype%5D=equals&where%5B0%5D%5Bfield%5D=emailAddress&where%5B0%5D%5Bvalue%5D=${ENCODED}" \
        2>/dev/null || echo '{"total":0}')
    TOTAL=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo 0)
    if [[ "$TOTAL" -ge 1 ]]; then
        FOUND=true
        ELAPSED=$i
        break
    fi
    printf "    [%2ds] contact not yet visible...\r" "$i"
    sleep 1
done
echo ""

if $FOUND; then
    echo "PASS: EspoCRM contact for ${TEST_EMAIL} created in ${ELAPSED}s (within the ${TIMEOUT}s QA5 SLA)."
else
    echo "FAIL: EspoCRM contact for ${TEST_EMAIL} not found after ${TIMEOUT}s."
    echo "      Check: docker compose logs espocrm_consumer"
    exit 1
fi

# ── 4. Durability test pointer ───────────────────────────────────────────────
echo ""
echo "Durability (QA5 'survives consumer downtime'): run ./scripts/test-durability.sh"
echo "  It stops the consumer, publishes N orders, restarts RabbitMQ to prove on-disk"
echo "  persistence, then drains with zero loss."
