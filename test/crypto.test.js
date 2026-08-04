import test from 'node:test';
import assert from 'node:assert/strict';
import { decryptJSON, encryptJSON, signSession, verifySession } from '../lib/crypto.js';

test('session tokens are signed and expire', () => {
  process.env.SESSION_SECRET = 'test-secret-that-is-long-enough';
  const token = signSession({ sub: 'user_1' }, 1_000_000);
  assert.equal(verifySession(token, 1_000_000).sub, 'user_1');
  assert.throws(() => verifySession(`${token}x`, 1_000_000));
});

test('service tokens use authenticated encryption', () => {
  process.env.TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
  const encrypted = encryptJSON({ access_token: 'secret' });
  assert.equal(decryptJSON(encrypted).access_token, 'secret');
  assert.doesNotMatch(encrypted, /secret/);
});
