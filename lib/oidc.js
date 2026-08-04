import crypto from 'node:crypto';

const cache = new Map();

function decodeJSON(segment) {
  return JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));
}

async function keysFor(url) {
  const existing = cache.get(url);
  if (existing && existing.expiresAt > Date.now()) return existing.keys;
  const response = await fetch(url, { headers: { accept: 'application/json' } });
  if (!response.ok) throw new Error('identity_keys_unavailable');
  const payload = await response.json();
  if (!Array.isArray(payload.keys)) throw new Error('identity_keys_invalid');
  cache.set(url, { keys: payload.keys, expiresAt: Date.now() + 6 * 60 * 60 * 1000 });
  return payload.keys;
}

function audienceMatches(actual, expected) {
  return Array.isArray(actual) ? actual.includes(expected) : actual === expected;
}

export async function verifyIdentityToken(token, { issuers, audience, jwksURL }) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) throw new Error('invalid_identity_token');
  const [headerText, payloadText, signatureText] = parts;
  const header = decodeJSON(headerText);
  const payload = decodeJSON(payloadText);
  if (header.alg !== 'RS256' || !header.kid) throw new Error('unsupported_identity_token');
  const keys = await keysFor(jwksURL);
  const jwk = keys.find((key) => key.kid === header.kid && key.kty === 'RSA');
  if (!jwk) throw new Error('identity_key_not_found');
  const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const valid = crypto.verify(
    'RSA-SHA256',
    Buffer.from(`${headerText}.${payloadText}`),
    publicKey,
    Buffer.from(signatureText, 'base64url')
  );
  if (!valid) throw new Error('invalid_identity_signature');
  const now = Math.floor(Date.now() / 1000);
  if (!issuers.includes(payload.iss)) throw new Error('invalid_identity_issuer');
  if (!audienceMatches(payload.aud, audience)) throw new Error('invalid_identity_audience');
  if (!payload.exp || payload.exp < now - 30) throw new Error('expired_identity_token');
  if (payload.iat && payload.iat > now + 120) throw new Error('invalid_identity_time');
  if (!payload.sub) throw new Error('invalid_identity_subject');
  return payload;
}
