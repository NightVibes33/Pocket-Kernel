import { completeGoogleAuth } from '../../../lib/account-auth.js';

export default async function handler(req, res) {
  try {
    const code = String(req.query.code || '');
    const state = String(req.query.state || '');
    if (!code || !state) throw new Error('invalid_oauth_callback');
    const ticket = await completeGoogleAuth(req, code, state);
    res.statusCode = 302;
    res.setHeader('location', `pocketkernel-auth://signed-in?ticket=${encodeURIComponent(ticket)}`);
    res.end();
  } catch (error) {
    res.statusCode = 302;
    res.setHeader('location', `pocketkernel-auth://signed-in?error=${encodeURIComponent(error.message)}`);
    res.end();
  }
}
