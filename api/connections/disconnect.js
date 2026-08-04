import { requireUser } from '../../lib/auth.js';
import { removeConnection } from '../../lib/connections.js';
import { provider } from '../../lib/providers.js';
import { json, method, readJSON } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const user = requireUser(req);
    const body = await readJSON(req);
    const name = String(body.provider || '').toLowerCase();
    provider(name);
    await removeConnection(user.id, name);
    json(res, 200, { disconnected: name });
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}
