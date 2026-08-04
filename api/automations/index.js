import { requireUser } from '../../lib/auth.js';
import { randomID } from '../../lib/crypto.js';
import { getJSON, putJSON, redis } from '../../lib/redis.js';
import { json, method, readJSON } from '../../lib/http.js';

const userIndex = (userID) => `pk:automations:${userID}`;
const automationKey = (id) => `pk:automation:${id}`;

export default async function handler(req, res) {
  try {
    const user = requireUser(req);
    if (req.method === 'GET') {
      const ids = (await redis('SMEMBERS', userIndex(user.id))) || [];
      const items = (await Promise.all(ids.map((id) => getJSON(automationKey(id))))).filter(Boolean);
      return json(res, 200, { automations: items.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))) });
    }
    if (req.method === 'POST') {
      const body = await readJSON(req);
      const id = randomID();
      const automation = {
        id,
        userID: user.id,
        title: String(body.title || 'Untitled automation').slice(0, 200),
        prompt: String(body.prompt || '').slice(0, 20000),
        steps: Array.isArray(body.steps) ? body.steps.slice(0, 20) : [],
        enabled: body.enabled !== false,
        nextRunAt: body.nextRunAt || null,
        repeatSeconds: Math.max(0, Math.min(Number(body.repeatSeconds || 0), 31_536_000)),
        createdAt: new Date().toISOString()
      };
      if (!automation.steps.length) return json(res, 400, { error: 'steps_required' });
      await putJSON(automationKey(id), automation);
      await redis('SADD', userIndex(user.id), id);
      if (automation.enabled && automation.nextRunAt) await redis('ZADD', 'pk:due', new Date(automation.nextRunAt).getTime(), id);
      return json(res, 201, { automation });
    }
    method(req, res, ['GET', 'POST']);
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}
