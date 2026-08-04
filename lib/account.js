import crypto from 'node:crypto';
import { randomID, sha256, signSession } from './crypto.js';
import { deleteKey, getJSON, putJSON } from './redis.js';

const emailIndexKey = (email) => `pk:user:email:${sha256(email)}`;
const oidcIndexKey = (provider, subject) => `pk:user:oidc:${provider}:${sha256(subject)}`;
const userKey = (id) => `pk:user:${id}`;
const loginCodeKey = (code) => `pk:login-code:${code}`;

export function normalizeEmail(value) {
  const email = String(value || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 320) throw new Error('invalid_email');
  return email;
}

function validatePassword(password) {
  const value = String(password || '');
  if (value.length < 8 || value.length > 256) throw new Error('invalid_password');
  return value;
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('base64url')) {
  const hash = crypto.scryptSync(validatePassword(password), salt, 64).toString('base64url');
  return { salt, hash };
}

function verifyPassword(password, salt, expectedText) {
  const actual = crypto.scryptSync(validatePassword(password), salt, 64);
  const expected = Buffer.from(expectedText, 'base64url');
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

export async function createEmailAccount({ email, password, displayName }) {
  const normalized = normalizeEmail(email);
  const existingID = await getJSON(emailIndexKey(normalized));
  if (existingID) throw new Error('email_already_registered');
  const id = `usr_${randomID(18)}`;
  const user = {
    id,
    email: normalized,
    displayName: String(displayName || '').trim().slice(0, 120) || null,
    provider: 'email',
    password: hashPassword(password),
    createdAt: new Date().toISOString()
  };
  await putJSON(userKey(id), user);
  await putJSON(emailIndexKey(normalized), id);
  return user;
}

export async function authenticateEmail({ email, password }) {
  const normalized = normalizeEmail(email);
  const id = await getJSON(emailIndexKey(normalized));
  if (!id) throw new Error('invalid_email_or_password');
  const user = await getJSON(userKey(id));
  if (!user?.password || !verifyPassword(password, user.password.salt, user.password.hash)) {
    throw new Error('invalid_email_or_password');
  }
  return user;
}

export async function upsertOIDCAccount({ provider, subject, email, displayName }) {
  if (!provider || !subject) throw new Error('invalid_identity');
  const index = oidcIndexKey(provider, subject);
  let id = await getJSON(index);
  let user = id ? await getJSON(userKey(id)) : null;
  if (!user) {
    id = `usr_${randomID(18)}`;
    user = {
      id,
      email: email ? normalizeEmail(email) : null,
      displayName: String(displayName || '').trim().slice(0, 120) || null,
      provider,
      subject,
      createdAt: new Date().toISOString()
    };
  } else {
    if (!user.email && email) user.email = normalizeEmail(email);
    if (!user.displayName && displayName) user.displayName = String(displayName).trim().slice(0, 120) || null;
  }
  await putJSON(userKey(id), user);
  await putJSON(index, id);
  if (user.email) {
    const emailKey = emailIndexKey(user.email);
    const existing = await getJSON(emailKey);
    if (!existing) await putJSON(emailKey, id);
  }
  return user;
}

export function authResponse(user) {
  const token = signSession({ sub: user.id, email: user.email || null, provider: user.provider });
  return {
    userID: user.id,
    token,
    expiresIn: 2_592_000,
    profile: {
      id: user.id,
      email: user.email || null,
      displayName: user.displayName || null,
      provider: user.provider
    }
  };
}

export async function createLoginCode(response) {
  const code = randomID(24);
  await putJSON(loginCodeKey(code), response, 300);
  return code;
}

export async function consumeLoginCode(code) {
  const key = loginCodeKey(String(code || ''));
  const response = await getJSON(key);
  if (!response) throw new Error('invalid_or_expired_login_code');
  await deleteKey(key);
  return response;
}
