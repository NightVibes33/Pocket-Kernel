import { getJSON, deleteKey } from '../../lib/redis.js';
import { exchangeCode } from '../../lib/providers.js';
import { saveConnection } from '../../lib/connections.js';

export default async function handler(req, res) {
  const url = new URL(req.url, `https://${req.headers.host}`);
  const state = url.searchParams.get('state');
  const code = url.searchParams.get('code');
  const provider = url.searchParams.get('provider');
  if (!state || !code || !provider) {
    res.statusCode = 400;
    return res.end('Invalid OAuth callback.');
  }
  try {
    const pending = await getJSON(`pk:oauth:${state}`);
    if (!pending || pending.provider !== provider) throw new Error('invalid_state');
    const tokens = await exchangeCode(req, provider, code, pending.verifier);
    await saveConnection(pending.userID, provider, tokens);
    await deleteKey(`pk:oauth:${state}`);
    res.statusCode = 302;
    res.setHeader('location', `${pending.appCallback}?provider=${encodeURIComponent(provider)}&status=connected`);
    res.end();
  } catch (error) {
    res.statusCode = 302;
    res.setHeader('location', `pocketkernel://oauth-complete?status=error&message=${encodeURIComponent(error.message)}`);
    res.end();
  }
}
