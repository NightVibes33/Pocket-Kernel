import { authenticateApple } from '../../lib/account-auth.js';
import { json, method, readJSON } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    const result = await authenticateApple(String(body.identityToken || ''), String(body.nonce || ''), {
      name: body.name ? String(body.name).slice(0, 160) : null,
      email: body.email ? String(body.email).slice(0, 320) : null
    });
    json(res, 200, result);
  } catch (error) {
    json(res, 400, { error: error.message === 'invalid_identity_token' ? 'invalid_apple_token' : error.message });
  }
}
