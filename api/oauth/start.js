import { requireUser } from '../../lib/auth.js';
import { authorizationURL, provider } from '../../lib/providers.js';
import { randomID, sha256 } from '../../lib/crypto.js';
import { putJSON } from '../../lib/redis.js';
import { json, method, readJSON } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const user = requireUser(req);
    const body = await readJSON(req);
    const name = String(body.provider || '').toLowerCase();
    provider(name);
    const state = randomID();
    const verifier = randomID(32);
    const challenge = sha256(verifier);
    await putJSON(`pk:oauth:${state}`, { userID: user.id, provider: name, verifier, appCallback: 'pocketkernel://oauth-complete' }, 600);
    json(res, 200, { authorizationURL: authorizationURL(req, name, state, challenge), state });
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}
