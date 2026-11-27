import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 30 },
    { duration: '1m',  target: 60 },
    { duration: '20s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'https://34.110.231.216.nip.io';

export default function () {
  const res = http.get(`${BASE_URL}/quotes?pair=USD/PEN&limit=20`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(0.2);
}
