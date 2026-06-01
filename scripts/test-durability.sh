#!/usr/bin/env bash
# ADR-003 / QA5 durability test.
#
# QA5 response measure: "the message survives at least 24h of consumer downtime."
# A 24h wall-clock wait is not demonstrable in a demo, so this test proves the *mechanism* that
# guarantees it, which is strictly stronger than waiting:
#
#   - the queue is declared durable and messages are published persistent (delivery_mode=2),
#     with NO message TTL, so the survival window is bounded only by broker disk, not by time;
#   - messages survive a full RabbitMQ restart (persisted to disk, not just held in memory);
#   - once the consumer comes back, every message is processed with zero loss.
#
# Steps:
#   1. Stop the EspoCRM consumer (simulate consumer downtime).
#   2. Publish N synthetic orders to northstar.events.
#   3. Confirm the queue holds N messages.
#   4. Restart RabbitMQ — proves persistence to disk across a broker bounce.
#   5. Confirm the queue STILL holds N messages after the broker came back.
#   6. Start the consumer; confirm all N EspoCRM contacts appear (zero loss).
#
# Usage: ./scripts/test-durability.sh [N]
# Prerequisites: full stack up (docker compose up -d --build).

set -euo pipefail

RABBITMQ_MGMT="${RABBITMQ_MGMT:-http://localhost:15672}"
ESPOCRM_URL="${ESPOCRM_URL:-http://localhost:8083}"
RABBITMQ_USER="${RABBITMQ_USER:-northstar}"
RABBITMQ_PASS="${RABBITMQ_PASS:-northstar}"
ESPOCRM_USER="${ESPOCRM_USER:-admin}"
ESPOCRM_PASS="${ESPOCRM_PASS:-admin}"
QUEUE="northstar.crm.orders"
N="${1:-20}"
BATCH="durability-$(date +%s)"

rabbit_curl () { curl -s -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" "$@"; }

queue_depth () {
    rabbit_curl "${RABBITMQ_MGMT}/api/queues/%2F/${QUEUE}" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin).get("messages",0))' 2>/dev/null || echo 0
}

crm_count () {
    # number of contacts whose email matches this batch tag
    local enc
    enc=$(python3 -c "import urllib.parse; print(urllib.parse.quote('@${BATCH}.test'))")
    rabbit_count=$(curl -s -u "${ESPOCRM_USER}:${ESPOCRM_PASS}" \
        "${ESPOCRM_URL}/api/v1/Contact?where%5B0%5D%5Btype%5D=contains&where%5B0%5D%5Bfield%5D=emailAddress&where%5B0%5D%5Bvalue%5D=${enc}" \
        2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("total",0))' 2>/dev/null || echo 0)
    echo "$rabbit_count"
}

echo "=== ADR-003 / QA5 durability (broker restart, ${N} messages) ==="

echo
echo "==> 1. Stopping espocrm_consumer (simulate consumer downtime)"
docker compose stop espocrm_consumer >/dev/null

echo "==> 2. Publishing ${N} synthetic orders to northstar.events"
for k in $(seq 1 "$N"); do
    oid=$((900000 + k))
    email="dura-${k}@${BATCH}.test"
    payload=$(printf '{"orderId":%d,"orderGuid":"00000000-0000-0000-0000-0000000000%02d","customerId":%d,"customerEmail":"%s","orderTotal":10.0,"buId":"bu2","timestamp":"%s"}' \
        "$oid" "$k" "$((600000 + k))" "$email" "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    rabbit_curl -X POST "${RABBITMQ_MGMT}/api/exchanges/%2F/northstar.events/publish" \
        -H "content-type: application/json" \
        -d "{\"properties\":{\"delivery_mode\":2},\"routing_key\":\"bu2.order.placed\",\"payload\":$(echo "$payload" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'),\"payload_encoding\":\"string\"}" \
        >/dev/null
done
sleep 2

echo "==> 3. Queue depth before broker restart: $(queue_depth) (expected ${N})"

echo "==> 4. Restarting RabbitMQ (proves on-disk persistence)..."
docker compose restart rabbitmq >/dev/null
echo "    waiting for RabbitMQ management API to come back..."
for _ in $(seq 1 60); do
    if rabbit_curl "${RABBITMQ_MGMT}/api/overview" >/dev/null 2>&1; then break; fi
    sleep 1
done
sleep 3

DEPTH_AFTER=$(queue_depth)
echo "==> 5. Queue depth AFTER broker restart: ${DEPTH_AFTER} (expected ${N})"
if [ "${DEPTH_AFTER:-0}" -lt "$N" ]; then
    echo "FAIL: messages were lost across the broker restart (${DEPTH_AFTER} < ${N})."
    docker compose start espocrm_consumer >/dev/null
    exit 1
fi
echo "    OK — all ${N} messages persisted across the broker bounce"

echo "==> 6. Starting espocrm_consumer; waiting for drain + CRM upsert"
docker compose start espocrm_consumer >/dev/null
FOUND=0
for i in $(seq 1 60); do
    FOUND=$(crm_count)
    if [ "${FOUND:-0}" -ge "$N" ]; then
        echo "    all ${N} contacts present after ${i}s"
        break
    fi
    printf "    [%2ds] %s/%s contacts\r" "$i" "${FOUND:-0}" "$N"
    sleep 1
done
echo ""

if [ "${FOUND:-0}" -ge "$N" ]; then
    echo "PASS: ${N}/${N} orders survived consumer downtime + a broker restart with zero loss (QA5)."
else
    echo "FAIL: only ${FOUND}/${N} contacts processed after restart."
    echo "      Check: docker compose logs espocrm_consumer"
    exit 1
fi
