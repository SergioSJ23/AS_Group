// ADR-003 evidence: drives a steady stream of add-to-cart operations on bu1.
// Operator can `docker pause espocrm_consumer` mid-run; `outbox_unpublished_rows`
// should climb, then drain back to ~0 within seconds of `docker unpause`.
//
// Note: full one-page checkout requires anti-forgery tokens and a multi-step session
// flow. For demo evidence we focus on the *outbox write* path: add-to-cart already
// triggers the entity events the OutboxRelay plugin's consumer listens for in the
// nopCommerce upstream test catalog. If finer-grained checkout coverage is needed,
// extend this script with cookie-jar + token extraction.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { BU, pick } from '../lib/config.js';

export const options = {
  scenarios: {
    checkout: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '90s', target: 25 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
      tags: { scenario: 'checkout' },
    },
  },
  thresholds: {
    'http_req_failed{scenario:checkout}': ['rate<0.05'],
  },
};

export default function () {
  const bu = BU.bu1;
  const slug = pick(bu.products);

  // 1. Load the product page — establishes session, returns add-to-cart form.
  const page = http.get(`${bu.base}/${slug}`, {
    tags: { scenario: 'checkout', step: 'product' },
  });
  check(page, { 'product 200': (r) => r.status === 200 });

  // 2. Extract product id from the form (best effort — graceful if regex misses).
  const m = page.body && page.body.match(/name="product_attribute_[^"]*"|data-productid="(\d+)"|addproducttocart\/(?:catalog|details)\/(\d+)/);
  const productId = m && (m[1] || m[2]);

  if (productId) {
    http.post(`${bu.base}/addproducttocart/catalog/${productId}/1/1`, null, {
      tags: { scenario: 'checkout', step: 'add-to-cart' },
    });
  }

  sleep(1 + Math.random());
}
