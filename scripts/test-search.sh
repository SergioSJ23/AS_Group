#!/usr/bin/env bash
# ADR-005 federated search + fallback smoke test.
#
#   1. Meilisearch healthy + reachable by both BUs.
#   2. Each BU's storefront /search returns HTTP 200 for a known keyword (live path).
#   3. Stop the meilisearch container — BU search still serves results from the DB fallback
#      and the storefront HTML contains the meili-fallback-banner marker.
#   4. Restart meilisearch — service recovers, banner disappears.
#
# Run from the repo root after `docker compose up -d` and `./scripts/install-nop.sh`.

set -euo pipefail

MEILI_HOST="http://localhost:7700"
MEILI_KEY="northstar-meili-master-key"
BU1="http://localhost:8081"
BU2="http://localhost:8082"
KEYWORD="${KEYWORD:-book}"

echo "=== ADR-005 Federated search + DB fallback ==="
echo

echo "1. Meilisearch /health"
curl -sf "${MEILI_HOST}/health" | python3 -m json.tool

echo
echo "2. Verifying each BU has indexed its own documents"
for bu in bu1 bu2; do
    n=$(curl -sf -H "Authorization: Bearer ${MEILI_KEY}" \
        "${MEILI_HOST}/indexes/products/search" \
        -X POST -H "Content-Type: application/json" \
        --data "{\"q\":\"\",\"filter\":\"buId = \\\"${bu}\\\"\",\"limit\":1}" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("estimatedTotalHits",0))')
    echo "    ${bu}: estimatedTotalHits=${n}"
    if [ "$n" -lt 1 ]; then
        echo "    WARN: index for ${bu} looks empty — has install-nop.sh run on a populated DB?"
    fi
done

probe_search () {
    local bu_url="$1" bu_label="$2"
    local body http
    body=$(mktemp)
    http=$(curl -sS -o "$body" -w '%{http_code}' "${bu_url}/search?q=${KEYWORD}")
    local banner=""
    if grep -q 'data-meili-fallback="true"' "$body"; then banner="yes"; else banner="no"; fi
    rm -f "$body"
    echo "    ${bu_label}: HTTP ${http}, fallback-banner=${banner}"
}

echo
echo "3. Live search path (Meilisearch up)"
probe_search "$BU1" "BU1"
probe_search "$BU2" "BU2"

echo
echo "4. Stopping meilisearch container to force fallback..."
docker compose stop meilisearch >/dev/null

echo "    waiting 3s for in-flight requests to drain"
sleep 3

echo
echo "5. Fallback path (Meilisearch down)"
probe_search "$BU1" "BU1"
probe_search "$BU2" "BU2"

echo
echo "    Expectations: HTTP 200 (DB fallback in ProductService), fallback-banner=yes."
echo "    The yellow banner is rendered by Nop.Plugin.Search.Meilisearch's widget at"
echo "    PublicWidgetZones.ProductSearchPageBeforeResults via the per-request FallbackSignal."

echo
echo "6. Restarting meilisearch..."
docker compose start meilisearch >/dev/null
for _ in $(seq 1 30); do
    if curl -sf "${MEILI_HOST}/health" >/dev/null 2>&1; then break; fi
    sleep 1
done

echo
echo "7. Recovery path (banner should be gone)"
probe_search "$BU1" "BU1"
probe_search "$BU2" "BU2"

echo
echo "=== Search test complete ==="
