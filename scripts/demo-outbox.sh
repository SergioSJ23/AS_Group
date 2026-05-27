#!/usr/bin/env bash
# Demo: ADR-003 outbox durability through a CRM consumer outage.
#
# Inserts N synthetic OutboxMessage rows on db_bu1 (the OutboxRelayService picks
# them up every 5 s and publishes to RabbitMQ `northstar.crm.orders`). To prove
# the durability claim, the EspoCRM consumer is paused first so messages pile up
# in the queue rather than being delivered. After ~30 s we unpause the consumer
# and the queue drains — no data lost.
#
# Watch on the Grafana dashboard (row "ADR-003"):
#   * "Outbox backlog (unpublished rows)" — climbs while rabbit is *also* paused
#     (skip that step for the CRM-outage variant), otherwise stays near 0
#   * "Publish rate + RabbitMQ queue depth" — rabbitmq_queue_messages climbs
#     during the CRM pause and drops to 0 after unpause
#   * "Outbox publish latency" — p50/p95 plot once messages publish

set -euo pipefail

ts() { date +'%H:%M:%S'; }
banner() { echo; echo "[$(ts)] ───── $* ─────"; }

N="${N:-50}"
BU="${BU:-bu1}"
DB_CONTAINER="northstar-db_${BU}-1"
DB_NAME="nop_${BU}"
CONSUMER_CONTAINER="northstar-espocrm_consumer-1"

queue_depth() {
  curl -s 'http://localhost:9090/api/v1/query?query=rabbitmq_queue_messages%7Bqueue%3D%22northstar.crm.orders%22%7D' \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(int(float(r[0]["value"][1])) if r else "n/a")'
}

cleanup() {
  echo
  echo "[$(ts)] cleanup: making sure consumer is running"
  docker unpause "$CONSUMER_CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

banner "Pausing espocrm_consumer — relay will publish but no one will consume"
docker pause "$CONSUMER_CONTAINER"

banner "Inserting $N synthetic outbox rows on $DB_NAME"
docker exec "$DB_CONTAINER" psql -U nop -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
INSERT INTO \"OutboxMessage\" (\"BuId\",\"EventType\",\"Payload\",\"CreatedAt\")
SELECT '$BU',
       'OrderPlaced',
       json_build_object(
         'orderId',  9000 + g,
         'buId',     '$BU',
         'customer', 'demo+' || g || '@northstar.local',
         'total',    round((random()*200 + 20)::numeric, 2),
         'placedAt', now()
       )::text,
       now()
FROM generate_series(1, $N) g;
" >/dev/null
echo "  inserted $N rows"

banner "Waiting 15s for OutboxRelayService to pick them up (polls every 5s)"
sleep 15
echo "  rabbitmq_queue_messages{northstar.crm.orders} = $(queue_depth)  (expected ≈ $N)"

banner "Holding the outage for 20s so the dashboard panel shows the plateau"
for i in 1 2 3 4; do
  sleep 5
  echo "  [$(ts)] queue depth = $(queue_depth)"
done

banner "Unpausing espocrm_consumer — queue should drain"
docker unpause "$CONSUMER_CONTAINER"

banner "Watching queue drain for 30s"
for i in 1 2 3 4 5 6; do
  sleep 5
  echo "  [$(ts)] queue depth = $(queue_depth)"
done

banner "Done. Grafana row 'ADR-003' should show: queue climbed to ~$N, then drained to 0."
echo "  Tip: variant for outbox_unpublished_rows climbing — additionally"
echo "       'docker pause northstar-rabbitmq-1' before the inserts."
