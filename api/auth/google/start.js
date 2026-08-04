import { startGoogleAuth } from '../../../lib/account-auth.js';
import { json, method } from '../../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try { json(res, 200, { authorizationURL: await startGoogleAuth(req) }); }
  catch (error) { json(res, 400, { error: error.message }); }
}
