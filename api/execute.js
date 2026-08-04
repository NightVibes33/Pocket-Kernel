import { requireUser } from '../lib/auth.js';
import { executeServiceAction } from '../lib/executor.js';
import { json, method, readJSON } from '../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const user = requireUser(req);
    const body = await readJSON(req);
    const provider = String(body.provider || '').toLowerCase();
    const action = String(body.action || '');
    const input = body.input && typeof body.input === 'object' ? body.input : {};
    const result = await executeServiceAction(user.id, provider, action, input);
    json(res, 200, { ok: true, result });
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}
