import { requireUser } from '../../lib/auth.js';
import { executeServiceAction } from '../../lib/executor.js';
import { deleteKey, getJSON, putJSON, redis } from '../../lib/redis.js';
import { json, method, readJSON } from '../../lib/http.js';

const automationKey = (id) => `pk:automation:${id}`;
const userIndex = (userID) => `pk:automations:${userID}`;

async function executeNow(automation) {
  let ok = true;
  let error = null;
  for (const step of automation.steps || []) {
    if (step.kind !== 'service') continue;
    try {
      await executeServiceAction(automation.userID, step.provider, step.action, step.input || {});
    } catch (value) {
      ok = false;
      error = value.message;
      break;
    }
  }
  automation.lastRunAt = new Date().toISOString();
  automation.lastRunOK = ok;
  automation.lastError = error;
  await putJSON(automationKey(automation.id), automation);
  if (!ok) throw new Error(error || 'automation_failed');
  return automation;
}

export default async function handler(req, res) {
  if (!method(req, res, ['PATCH', 'POST', 'DELETE'])) return;
  try {
    const user = requireUser(req);
    const id = String(req.query.id || '');
    if (!/^[A-Za-z0-9_-]{8,200}$/.test(id)) return json(res, 400, { error: 'invalid_automation_id' });

    const automation = await getJSON(automationKey(id));
    if (!automation || automation.userID !== user.id) return json(res, 404, { error: 'automation_not_found' });

    if (req.method === 'DELETE') {
      await deleteKey(automationKey(id));
      await redis('SREM', userIndex(user.id), id);
      await redis('ZREM', 'pk:due', id);
      return json(res, 200, { deleted: id });
    }

    const body = await readJSON(req);
    if (req.method === 'POST') {
      if (body.action !== 'run') return json(res, 400, { error: 'unsupported_action' });
      const updated = await executeNow(automation);
      return json(res, 200, { automation: updated });
    }

    if (typeof body.enabled !== 'boolean') return json(res, 400, { error: 'enabled_required' });
    automation.enabled = body.enabled;
    automation.updatedAt = new Date().toISOString();
    if (!automation.enabled) {
      await redis('ZREM', 'pk:due', id);
    } else if (automation.nextRunAt) {
      const score = Math.max(Date.now(), new Date(automation.nextRunAt).getTime());
      if (Number.isFinite(score)) await redis('ZADD', 'pk:due', score, id);
    }
    await putJSON(automationKey(id), automation);
    return json(res, 200, { automation });
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}
