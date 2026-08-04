import { bearer } from './http.js';
import { verifySession } from './crypto.js';

export function requireUser(req) {
  const token = bearer(req);
  const payload = verifySession(token);
  if (!payload.sub) throw new Error('invalid_session');
  return { id: payload.sub, deviceID: payload.deviceID || null };
}
