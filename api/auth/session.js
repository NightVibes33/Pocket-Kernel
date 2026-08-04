import { requireUser } from '../../lib/auth.js';
import { accountProfile } from '../../lib/account-auth.js';
import { json, method } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['GET'])) return;
  try {
    const user = requireUser(req);
    const profile = await accountProfile(user.id);
    if (!profile) return json(res, 401, { error: 'account_not_found' });
    json(res, 200, { profile: { id: profile.id, email: profile.email, name: profile.name, provider: profile.provider } });
  } catch (error) { json(res, 401, { error: error.message }); }
}
