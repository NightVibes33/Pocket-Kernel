import { signSession, sha256 } from '../../lib/crypto.js';
import { json, method, readJSON } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    const deviceID = String(body.deviceID || '');
    if (!/^[A-Za-z0-9._-]{16,200}$/.test(deviceID)) return json(res, 400, { error: 'invalid_device_id' });
    const userID = `device_${sha256(deviceID).slice(0, 32)}`;
    const token = signSession({ sub: userID, deviceID });
    json(res, 200, { userID, token, expiresIn: 2_592_000 });
  } catch (error) {
    json(res, 500, { error: error.message });
  }
}
