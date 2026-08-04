import { required } from './env.js';

export async function redis(...command) {
  const url = required('UPSTASH_REDIS_REST_URL').replace(/\/$/, '');
  const token = required('UPSTASH_REDIS_REST_TOKEN');
  const response = await fetch(url, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(command)
  });
  if (!response.ok) throw new Error(`redis_${response.status}`);
  const payload = await response.json();
  if (payload.error) throw new Error(`redis_${payload.error}`);
  return payload.result;
}

export async function putJSON(key, value, ttlSeconds) {
  const args = ttlSeconds ? ['SET', key, JSON.stringify(value), 'EX', ttlSeconds] : ['SET', key, JSON.stringify(value)];
  return redis(...args);
}

export async function getJSON(key) {
  const value = await redis('GET', key);
  return value ? JSON.parse(value) : null;
}

export async function deleteKey(key) {
  return redis('DEL', key);
}
