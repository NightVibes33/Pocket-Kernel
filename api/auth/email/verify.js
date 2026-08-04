import { verifyEmailCode } from '../../../lib/account-auth.js';
import { json, method, readJSON } from '../../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    json(res, 200, await verifyEmailCode(body.email, body.code));
  } catch (error) { json(res, 400, { error: error.message }); }
}
