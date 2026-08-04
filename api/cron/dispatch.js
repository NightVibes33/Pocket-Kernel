import { executeServiceAction } from '../../lib/executor.js';
import { getJSON, putJSON, redis } from '../../lib/redis.js';
import { json } from '../../lib/http.js';

export default async function handler(req, res) {
  const expected = process.env.CRON_SECRET;
  const authorization = req.headers.authorization;
  if (expected && authorization !== `Bearer ${expected}`) return json(res, 401, { error: 'unauthorized' });
  const now = Date.now();
  try {
    const ids = (await redis('ZRANGEBYSCORE', 'pk:due', 0, now, 'LIMIT', 0, 50)) || [];
    const results = [];
    for (const id of ids) {
      const automation = await getJSON(`pk:automation:${id}`);
      await redis('ZREM', 'pk:due', id);
      if (!automation?.enabled) continue;
      let ok = true;
      let error = null;
      for (const step of automation.steps) {
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
      if (automation.repeatSeconds > 0) {
        automation.nextRunAt = new Date(now + automation.repeatSeconds * 1000).toISOString();
        await redis('ZADD', 'pk:due', new Date(automation.nextRunAt).getTime(), id);
      } else {
        automation.nextRunAt = null;
      }
      await putJSON(`pk:automation:${id}`, automation);
      results.push({ id, ok, error });
    }
    json(res, 200, { dispatched: results.length, results });
  } catch (error) {
    json(res, 500, { error: error.message });
  }
}
