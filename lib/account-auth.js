import crypto from 'node:crypto';
import { randomID, sha256, signSession } from './crypto.js';
import { baseURL, required } from './env.js';
import { deleteKey, getJSON, putJSON, redis } from './redis.js';

const accountKey = (id) => `pk:account:${id}`;
const authStateKey = (id) => `pk:auth-state:${id}`;
const ticketKey = (id) => `pk:auth-ticket:${id}`;
const emailCodeKey = (emailHash) => `pk:email-code:${emailHash}`;

function base64URLDecode(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  return Buffer.from(normalized + '='.repeat((4 - normalized.length % 4) % 4), 'base64');
}

function decodeJWT(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) throw new Error('invalid_identity_token');
  const header = JSON.parse(base64URLDecode(parts[0]).toString('utf8'));
  const payload = JSON.parse(base64URLDecode(parts[1]).toString('utf8'));
  return { parts, header, payload };
}

async function verifyJWT(token, { jwksURL, issuer, audience }) {
  const { parts, header, payload } = decodeJWT(token);
  if (header.alg !== 'RS256' || !header.kid) throw new Error('invalid_identity_token');
  const response = await fetch(jwksURL, { headers: { accept: 'application/json' } });
  if (!response.ok) throw new Error('identity_keys_unavailable');
  const jwks = await response.json();
  const jwk = jwks.keys?.find((item) => item.kid === header.kid && item.kty === 'RSA');
  if (!jwk) throw new Error('identity_key_not_found');
  const key = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const valid = crypto.verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), key, base64URLDecode(parts[2]));
  if (!valid) throw new Error('invalid_identity_token');
  const now = Math.floor(Date.now() / 1000);
  if (Number(payload.exp || 0) <= now || Number(payload.iat || 0) > now + 300) throw new Error('expired_identity_token');
  const issuers = Array.isArray(issuer) ? issuer : [issuer];
  if (!issuers.includes(payload.iss)) throw new Error('invalid_identity_issuer');
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(audience)) throw new Error('invalid_identity_audience');
  return payload;
}

export async function authenticateApple(identityToken, nonce, supplied = {}) {
  const audience = process.env.APPLE_CLIENT_ID || 'com.nightvibes33.pocketkernel';
  const payload = await verifyJWT(identityToken, {
    jwksURL: 'https://appleid.apple.com/auth/keys',
    issuer: 'https://appleid.apple.com',
    audience
  });
  if (!nonce || payload.nonce !== sha256(nonce)) throw new Error('invalid_apple_nonce');
  const id = `apple_${sha256(String(payload.sub)).slice(0, 32)}`;
  const existing = await getJSON(accountKey(id));
  const profile = {
    id,
    provider: 'apple',
    email: payload.email || supplied.email || existing?.email || null,
    name: supplied.name || existing?.name || null,
    createdAt: existing?.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };
  await putJSON(accountKey(id), profile);
  return issueAccountSession(profile);
}

export async function startGoogleAuth(req) {
  if (!process.env.GOOGLE_CLIENT_ID || !process.env.GOOGLE_CLIENT_SECRET) throw new Error('google_not_configured');
  const state = randomID();
  const verifier = crypto.randomBytes(32).toString('base64url');
  const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
  await putJSON(authStateKey(state), { verifier, createdAt: Date.now() }, 600);
  const redirectURI = `${baseURL(req)}/api/auth/google/callback`;
  const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  url.searchParams.set('client_id', process.env.GOOGLE_CLIENT_ID);
  url.searchParams.set('redirect_uri', redirectURI);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', 'openid email profile');
  url.searchParams.set('state', state);
  url.searchParams.set('code_challenge', challenge);
  url.searchParams.set('code_challenge_method', 'S256');
  url.searchParams.set('prompt', 'select_account');
  return url.toString();
}

export async function completeGoogleAuth(req, code, state) {
  const record = await getJSON(authStateKey(state));
  await deleteKey(authStateKey(state));
  if (!record?.verifier) throw new Error('invalid_auth_state');
  const redirectURI = `${baseURL(req)}/api/auth/google/callback`;
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: required('GOOGLE_CLIENT_ID'),
      client_secret: required('GOOGLE_CLIENT_SECRET'),
      redirect_uri: redirectURI,
      grant_type: 'authorization_code',
      code_verifier: record.verifier
    })
  });
  const tokens = await tokenResponse.json().catch(() => ({}));
  if (!tokenResponse.ok || !tokens.id_token) throw new Error('google_exchange_failed');
  const payload = await verifyJWT(tokens.id_token, {
    jwksURL: 'https://www.googleapis.com/oauth2/v3/certs',
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
    audience: required('GOOGLE_CLIENT_ID')
  });
  const id = `google_${sha256(String(payload.sub)).slice(0, 32)}`;
  const existing = await getJSON(accountKey(id));
  const profile = {
    id,
    provider: 'google',
    email: payload.email || existing?.email || null,
    name: payload.name || existing?.name || null,
    createdAt: existing?.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };
  await putJSON(accountKey(id), profile);
  const ticket = randomID();
  await putJSON(ticketKey(ticket), issueAccountSession(profile), 120);
  return ticket;
}

export async function exchangeTicket(ticket) {
  const value = await getJSON(ticketKey(ticket));
  await deleteKey(ticketKey(ticket));
  if (!value) throw new Error('invalid_auth_ticket');
  return value;
}

export async function startEmailCode(email) {
  if (!process.env.RESEND_API_KEY || !process.env.EMAIL_FROM) throw new Error('email_not_configured');
  const normalized = normalizeEmail(email);
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = sha256(`${salt}:${code}`);
  await putJSON(emailCodeKey(sha256(normalized)), { salt, hash, attempts: 0 }, 600);
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { authorization: `Bearer ${process.env.RESEND_API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      from: process.env.EMAIL_FROM,
      to: [normalized],
      subject: `${code} is your PocketKernel code`,
      html: `<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;max-width:520px;margin:auto;padding:32px"><h1 style="font-size:28px">Sign in to PocketKernel</h1><p style="color:#555">Enter this one-time code in the app:</p><div style="font-size:38px;font-weight:700;letter-spacing:8px;padding:22px 0">${code}</div><p style="color:#777">This code expires in 10 minutes. If you didn’t request it, you can ignore this email.</p></div>`
    })
  });
  if (!response.ok) throw new Error('email_delivery_failed');
  return { sent: true, expiresIn: 600 };
}

export async function verifyEmailCode(email, code) {
  const normalized = normalizeEmail(email);
  const key = emailCodeKey(sha256(normalized));
  const record = await getJSON(key);
  if (!record || record.attempts >= 5 || !/^\d{6}$/.test(String(code || ''))) throw new Error('invalid_code');
  const actual = Buffer.from(sha256(`${record.salt}:${code}`));
  const expected = Buffer.from(record.hash);
  if (actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected)) {
    record.attempts += 1;
    await putJSON(key, record, 600);
    throw new Error('invalid_code');
  }
  await deleteKey(key);
  const id = `email_${sha256(normalized).slice(0, 32)}`;
  const existing = await getJSON(accountKey(id));
  const profile = {
    id,
    provider: 'email',
    email: normalized,
    name: existing?.name || null,
    createdAt: existing?.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };
  await putJSON(accountKey(id), profile);
  return issueAccountSession(profile);
}

export async function accountProfile(userID) {
  return getJSON(accountKey(userID));
}

export function issueAccountSession(profile) {
  return {
    userID: profile.id,
    token: signSession({ sub: profile.id, provider: profile.provider }),
    expiresIn: 2_592_000,
    profile: { id: profile.id, email: profile.email, name: profile.name, provider: profile.provider }
  };
}

function normalizeEmail(value) {
  const email = String(value || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320) throw new Error('invalid_email');
  return email;
}
