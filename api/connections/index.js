import { requireUser } from '../../lib/auth.js';
import { listConnections } from '../../lib/connections.js';
import { publicProviderList } from '../../lib/providers.js';
import { configuration } from '../../lib/env.js';
import { json, method } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['GET'])) return;
  try {
    const user = requireUser(req);
    json(res, 200, { connections: await listConnections(user.id), providers: publicProviderList(), configured: configuration().providers });
  } catch (error) {
    json(res, 401, { error: error.message });
  }
}
