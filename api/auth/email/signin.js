import { authResponse, authenticateEmail } from '../../../lib/account.js';
import { json, method, readJSON } from '../../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    const user = await authenticateEmail(body);
    json(res, 200, authResponse(user));
  } catch (error) {
    json(res, 401, { error: error.message });
  }
}
