import crypto from 'node:crypto';
import { required } from './env.js';

function b64url(data) {
  return Buffer.from(data).toString('base64url');
}

export function signSession(payload, now = Date.now()) {
  const secret = required('SESSION_SECRET');
  const body = { ...payload, iat: Math.floor(now / 1000), exp: Math.floor(now / 1000) + 60 * 60 * 24 * 30 };
  const encoded = b64url(JSON.stringify(body));
  const signature = crypto.createHmac('sha256', secret).update(encoded).digest('base64url');
  return `${encoded}.${signature}`;
}

export function verifySession(token, now = Date.now()) {
  if (!token || !token.includes('.')) throw new Error('invalid_session');
  const secret = required('SESSION_SECRET');
  const [encoded, signature] = token.split('.');
  const expected = crypto.createHmac('sha256', secret).update(encoded).digest();
  const actual = Buffer.from(signature, 'base64url');
  if (actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected)) throw new Error('invalid_session');
  const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
  if (!payload.exp || payload.exp < Math.floor(now / 1000)) throw new Error('expired_session');
  return payload;
}

function encryptionKey() {
  const raw = Buffer.from(required('TOKEN_ENCRYPTION_KEY'), 'base64');
  if (raw.length !== 32) throw new Error('invalid_TOKEN_ENCRYPTION_KEY');
  return raw;
}

export function encryptJSON(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, ciphertext].map((x) => x.toString('base64url')).join('.');
}

export function decryptJSON(value) {
  const [ivText, tagText, ciphertextText] = String(value).split('.');
  const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(), Buffer.from(ivText, 'base64url'));
  decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
  const plaintext = Buffer.concat([decipher.update(Buffer.from(ciphertextText, 'base64url')), decipher.final()]);
  return JSON.parse(plaintext.toString('utf8'));
}

export function randomID(bytes = 18) {
  return crypto.randomBytes(bytes).toString('base64url');
}

export function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('base64url');
}
