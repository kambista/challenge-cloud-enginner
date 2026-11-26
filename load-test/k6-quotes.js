import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL;
if (!BASE_URL) {
  throw new Error('Falta BASE_URL, ej: -e BASE_URL=https://34.1.2.3.nip.io');
}

export const options = {
  stages: [
    { duration: '1m', target: 20 },
    { duration: '3m', target: 80 },
    { duration: '4m', target: 80 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    'http_req_duration{name:GET /quotes}': ['p(95)<500'],
    'http_req_duration{name:POST /quotes}': ['p(95)<800'],
  },
};

const PAIRS = ['USD/PEN', 'EUR/PEN', 'USD/EUR'];
const JSON_HEADERS = { 'content-type': 'application/json' };

export default function () {
  const pair = PAIRS[Math.floor(Math.random() * PAIRS.length)];

  if (Math.random() < 0.2) {
    const buy = 3.6 + Math.random() * 0.2;
    const body = JSON.stringify({
      pair,
      buy: Number(buy.toFixed(4)),
      sell: Number((buy + 0.05).toFixed(4)),
      source: 'k6',
    });
    const res = http.post(`${BASE_URL}/quotes`, body, {
      headers: JSON_HEADERS,
      tags: { name: 'POST /quotes' },
    });
    check(res, { 'POST 2xx': (r) => r.status >= 200 && r.status < 300 });
  } else {
    const res = http.get(`${BASE_URL}/quotes?pair=${encodeURIComponent(pair)}&limit=20`, {
      tags: { name: 'GET /quotes' },
    });
    check(res, { 'GET 200': (r) => r.status === 200 });
  }

  sleep(0.2);
}
