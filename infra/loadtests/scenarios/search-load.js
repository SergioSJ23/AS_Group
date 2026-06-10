// ADR-005 evidence: drives search traffic against both BUs.
// Operator can `docker pause meilisearch` mid-run; the storefront should keep
// returning 200 via the DB fallback path, and `search_fallback_total` should climb.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { BU, pick } from '../lib/config.js';

export const options = {
  scenarios: {
    search: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '90s', target: 40 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
      tags: { scenario: 'search' },
    },
  },
  thresholds: {
    // Storefront must remain healthy even when meilisearch is paused.
    'http_req_failed{scenario:search}': ['rate<0.01'],
    'http_req_duration{scenario:search}': ['p(95)<5000'],
  },
};

export default function () {
  const bu = Math.random() < 0.5 ? BU.bu1 : BU.bu2;
  const q = pick(bu.searchTerms);
  const res = http.get(`${bu.base}/search/?q=${encodeURIComponent(q)}`, {
    tags: { scenario: 'search', bu: bu === BU.bu1 ? 'bu1' : 'bu2' },
  });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.5 + Math.random());
}
