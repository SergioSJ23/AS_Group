#!/usr/bin/env bash
# Pushes products from both BUs directly to Meilisearch via its REST API.
# Use this when install-nop.sh cannot log in to nopCommerce (e.g. admin password unknown)
# so the Group Portal at :8000 shows real products instead of the preview fallback.
#
# Idempotent: safe to run multiple times (documents are upserted by id).
# Requires: curl, Meilisearch running on localhost:7700.

set -euo pipefail

MEILI="${MEILI_URL:-http://localhost:7700}"
KEY="${MEILI_KEY:-northstar-meili-master-key}"
INDEX="products"

echo "==> Meilisearch direct seed — targeting ${MEILI}/indexes/${INDEX}"

# ── 1. Ensure the index exists ────────────────────────────────────────────────
echo "    ensuring index..."
curl -s -o /dev/null -X POST "${MEILI}/indexes" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"uid\": \"${INDEX}\", \"primaryKey\": \"id\"}" || true

# ── 2. Make buId filterable (required for per-BU search in nopCommerce plugin) ─
echo "    configuring filterable attributes..."
TASK=$(curl -s -X PATCH "${MEILI}/indexes/${INDEX}/settings/filterable-attributes" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d '["buId"]' | grep -o '"taskUid":[0-9]*' | grep -o '[0-9]*' || true)

# ── 3. Upsert BU1 products (HomeStyle) ───────────────────────────────────────
echo "    upserting BU1 (HomeStyle) products..."
curl -s -o /dev/null -X POST "${MEILI}/indexes/${INDEX}/documents?primaryKey=id" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "id":          "bu1-1",
      "productId":   1,
      "buId":        "bu1",
      "name":        "Linen Sofa",
      "description": "Handcrafted 3-seater sofa with solid oak legs.",
      "sku":         "HS-SOFA-001",
      "slug":        "linen-sofa",
      "price":       1249.00
    },
    {
      "id":          "bu1-2",
      "productId":   2,
      "buId":        "bu1",
      "name":        "Walnut Coffee Table",
      "description": "Solid walnut top, 120 × 60 cm.",
      "sku":         "HS-TABLE-001",
      "slug":        "walnut-coffee-table",
      "price":       449.00
    },
    {
      "id":          "bu1-3",
      "productId":   3,
      "buId":        "bu1",
      "name":        "Rattan Pendant Light",
      "description": "Handwoven rattan lamp, 40 cm diameter.",
      "sku":         "HS-LIGHT-001",
      "slug":        "rattan-pendant-light",
      "price":       129.00
    },
    {
      "id":          "bu1-4",
      "productId":   4,
      "buId":        "bu1",
      "name":        "Marble Table Lamp",
      "description": "White Carrara marble base with a linen shade.",
      "sku":         "HS-LIGHT-002",
      "slug":        "marble-table-lamp",
      "price":       189.00
    }
  ]'

# ── 4. Upsert BU2 products (WorkSpace) ───────────────────────────────────────
echo "    upserting BU2 (WorkSpace) products..."
curl -s -o /dev/null -X POST "${MEILI}/indexes/${INDEX}/documents?primaryKey=id" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "id":          "bu2-1",
      "productId":   1,
      "buId":        "bu2",
      "name":        "Ergonomic Mesh Chair",
      "description": "Full-mesh back, 4D armrests, lumbar support.",
      "sku":         "WS-CHAIR-001",
      "slug":        "ergonomic-mesh-chair",
      "price":       699.00
    },
    {
      "id":          "bu2-2",
      "productId":   2,
      "buId":        "bu2",
      "name":        "Adjustable Standing Desk",
      "description": "Electric sit-stand, 140 × 70 cm bamboo top.",
      "sku":         "WS-DESK-001",
      "slug":        "adjustable-standing-desk",
      "price":       849.00
    },
    {
      "id":          "bu2-3",
      "productId":   3,
      "buId":        "bu2",
      "name":        "27\" Ultrawide Monitor",
      "description": "QHD IPS panel, 144 Hz, USB-C 90W PD.",
      "sku":         "WS-MON-001",
      "slug":        "27-ultrawide-monitor",
      "price":       549.00
    },
    {
      "id":          "bu2-4",
      "productId":   4,
      "buId":        "bu2",
      "name":        "Cable Management Kit",
      "description": "Under-desk tray, 10 velcro ties, 3 cable clips.",
      "sku":         "WS-ACC-001",
      "slug":        "cable-management-kit",
      "price":       39.00
    }
  ]'

echo
echo "Done. Refresh http://localhost:8000 — products should appear in the portal."
echo "Note: slug-based links (/linen-sofa, etc.) only resolve after install-nop.sh"
echo "      completes successfully (nopCommerce must be fully installed)."
