import { authResponse, createEmailAccount } from '../../../lib/account.js';
import { json, method, readJSON } from '../../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    const user = await createEmailAccount(body);
    json(res, 201, authResponse(user));
  } catch (error) {
    const status = error.message === 'email_already_registered' ? 409 : 400;
    json(res, status, { error: error.message });
  }
}
