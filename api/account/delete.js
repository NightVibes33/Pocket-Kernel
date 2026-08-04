import { requireUser } from '../../lib/auth.js';
import { deleteKey, redis } from '../../lib/redis.js';
import { json, method } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['DELETE'])) return;
  try {
    const user = requireUser(req);

    const providers = (await redis('SMEMBERS', `pk:connections:${user.id}`)) || [];
    for (const provider of providers) {
      await deleteKey(`pk:connection:${user.id}:${provider}`);
    }
    await deleteKey(`pk:connections:${user.id}`);

    const automations = (await redis('SMEMBERS', `pk:automations:${user.id}`)) || [];
    for (const id of automations) {
      await deleteKey(`pk:automation:${id}`);
      await redis('ZREM', 'pk:due', id);
    }
    await deleteKey(`pk:automations:${user.id}`);

    json(res, 200, { deleted: true });
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}
