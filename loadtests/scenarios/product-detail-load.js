// ADR-004 evidence: streams product detail page traffic at bu1.
// Operator runs `./scripts/test-erp-failure.sh` mid-run (POST /admin/break to erp_bu1).
// `erp_breaker_state` should flip 0 → 2 (CLOSED → OPEN) after 5 consecutive failures;
// page responses stay 200 because StockResult falls back to cache.
// `./scripts/test-erp-recovery.sh` brings the breaker back through HALF-OPEN → CLOSED.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { BU, pick } from '../lib/config.js';

export const options = {
  scenarios: {
    product_detail: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 15 },
        { duration: '120s', target: 30 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
      tags: { scenario: 'product_detail' },
    },
  },
  thresholds: {
    // Storefront must keep serving 200 even when the ERP breaker is OPEN.
    'http_req_failed{scenario:product_detail}': ['rate<0.01'],
    'http_req_duration{scenario:product_detail}': ['p(95)<3000'],
  },
};

export default function () {
  const bu = BU.bu1;
  const slug = pick(bu.products);
  const res = http.get(`${bu.base}/${slug}`, {
    tags: { scenario: 'product_detail', bu: 'bu1' },
  });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.5 + Math.random());
}
