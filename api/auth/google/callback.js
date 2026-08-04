import { authResponse, createLoginCode, upsertOIDCAccount } from '../../../lib/account.js';
import { baseURL, required } from '../../../lib/env.js';
import { deleteKey, getJSON } from '../../../lib/redis.js';
import { verifyIdentityToken } from '../../../lib/oidc.js';

function redirect(res, location) {
  res.statusCode = 302;
  res.setHeader('location', location);
  res.end();
}

export default async function handler(req, res) {
  const url = new URL(req.url, baseURL(req));
  const state = url.searchParams.get('state');
  const code = url.searchParams.get('code');
  if (!state || !code) return redirect(res, 'pocketkernel://auth?error=google_sign_in_canceled');
  try {
    const key = `pk:auth:google:${state}`;
    const pending = await getJSON(key);
    await deleteKey(key);
    if (!pending) throw new Error('invalid_or_expired_google_state');
    const clientID = process.env.GOOGLE_AUTH_CLIENT_ID || required('GOOGLE_CLIENT_ID');
    const clientSecret = process.env.GOOGLE_AUTH_CLIENT_SECRET || required('GOOGLE_CLIENT_SECRET');
    const response = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientID,
        client_secret: clientSecret,
        redirect_uri: pending.redirectURI,
        grant_type: 'authorization_code',
        code_verifier: pending.verifier
      })
    });
    const token = await response.json();
    if (!response.ok || !token.id_token) throw new Error('google_token_exchange_failed');
    const claims = await verifyIdentityToken(token.id_token, {
      issuers: ['https://accounts.google.com', 'accounts.google.com'],
      audience: clientID,
      jwksURL: 'https://www.googleapis.com/oauth2/v3/certs'
    });
    const user = await upsertOIDCAccount({
      provider: 'google',
      subject: claims.sub,
      email: claims.email || null,
      displayName: claims.name || null
    });
    const loginCode = await createLoginCode(authResponse(user));
    redirect(res, `pocketkernel://auth?code=${encodeURIComponent(loginCode)}`);
  } catch (error) {
    redirect(res, `pocketkernel://auth?error=${encodeURIComponent(error.message)}`);
  }
}
