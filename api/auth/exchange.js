import { consumeLoginCode } from '../../lib/account.js';
import { json, method, readJSON } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    const response = await consumeLoginCode(body.code);
    json(res, 200, response);
  } catch (error) {
    json(res, 401, { error: error.message });
  }
}
