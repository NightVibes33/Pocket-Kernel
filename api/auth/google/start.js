import { baseURL, required } from '../../../lib/env.js';
import { randomID, sha256 } from '../../../lib/crypto.js';
import { putJSON } from '../../../lib/redis.js';
import { json, method } from '../../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['GET'])) return;
  try {
    const clientID = process.env.GOOGLE_AUTH_CLIENT_ID || required('GOOGLE_CLIENT_ID');
    const state = randomID(24);
    const verifier = randomID(48);
    const redirectURI = `${baseURL(req)}/api/auth/google/callback`;
    await putJSON(`pk:auth:google:${state}`, { verifier, redirectURI }, 600);
    const params = new URLSearchParams({
      client_id: clientID,
      redirect_uri: redirectURI,
      response_type: 'code',
      scope: 'openid email profile',
      state,
      code_challenge: sha256(verifier),
      code_challenge_method: 'S256',
      access_type: 'online',
      prompt: 'select_account'
    });
    json(res, 200, { authorizationURL: `https://accounts.google.com/o/oauth2/v2/auth?${params}` });
  } catch (error) {
    json(res, 503, { error: error.message });
  }
}
