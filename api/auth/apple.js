import { authResponse, upsertOIDCAccount } from '../../lib/account.js';
import { verifyIdentityToken } from '../../lib/oidc.js';
import { json, method, readJSON } from '../../lib/http.js';

export default async function handler(req, res) {
  if (!method(req, res, ['POST'])) return;
  try {
    const body = await readJSON(req);
    const audience = process.env.APPLE_CLIENT_ID || 'com.nightvibes33.pocketkernel';
    const claims = await verifyIdentityToken(body.identityToken, {
      issuers: ['https://appleid.apple.com'],
      audience,
      jwksURL: 'https://appleid.apple.com/auth/keys'
    });
    const user = await upsertOIDCAccount({
      provider: 'apple',
      subject: claims.sub,
      email: body.email || claims.email || null,
      displayName: body.displayName || null
    });
    json(res, 200, authResponse(user));
  } catch (error) {
    json(res, 401, { error: error.message });
  }
}
