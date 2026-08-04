import { baseURL, required } from './env.js';

const providers = {
  google: {
    authorize: 'https://accounts.google.com/o/oauth2/v2/auth',
    token: 'https://oauth2.googleapis.com/token',
    scopes: ['openid', 'email', 'https://www.googleapis.com/auth/gmail.modify', 'https://www.googleapis.com/auth/calendar.events', 'https://www.googleapis.com/auth/drive.file'],
    extra: { access_type: 'offline', prompt: 'consent' }
  },
  slack: {
    authorize: 'https://slack.com/oauth/v2/authorize',
    token: 'https://slack.com/api/oauth.v2.access',
    scopes: ['channels:read', 'chat:write', 'users:read', 'files:write']
  },
  discord: {
    authorize: 'https://discord.com/oauth2/authorize',
    token: 'https://discord.com/api/oauth2/token',
    scopes: ['identify', 'guilds', 'webhook.incoming']
  },
  reddit: {
    authorize: 'https://www.reddit.com/api/v1/authorize',
    token: 'https://www.reddit.com/api/v1/access_token',
    scopes: ['identity', 'read', 'submit', 'privatemessages'],
    extra: { duration: 'permanent' }
  },
  notion: {
    authorize: 'https://api.notion.com/v1/oauth/authorize',
    token: 'https://api.notion.com/v1/oauth/token',
    scopes: []
  }
};

export function provider(name) {
  const value = providers[name];
  if (!value) throw new Error('unsupported_provider');
  return value;
}

export function providerCredentials(name) {
  const prefix = name.toUpperCase();
  return { clientID: required(`${prefix}_CLIENT_ID`), clientSecret: required(`${prefix}_CLIENT_SECRET`) };
}

export function callbackURL(req, name) {
  return `${baseURL(req)}/api/oauth/callback?provider=${encodeURIComponent(name)}`;
}

export function authorizationURL(req, name, state, codeChallenge) {
  const config = provider(name);
  const credentials = providerCredentials(name);
  const url = new URL(config.authorize);
  url.searchParams.set('client_id', credentials.clientID);
  url.searchParams.set('redirect_uri', callbackURL(req, name));
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('state', state);
  if (config.scopes.length) url.searchParams.set(name === 'slack' ? 'scope' : 'scope', config.scopes.join(name === 'reddit' ? ' ' : ' '));
  if (codeChallenge) {
    url.searchParams.set('code_challenge', codeChallenge);
    url.searchParams.set('code_challenge_method', 'S256');
  }
  for (const [key, value] of Object.entries(config.extra || {})) url.searchParams.set(key, value);
  if (name === 'notion') url.searchParams.set('owner', 'user');
  return url.toString();
}

export async function exchangeCode(req, name, code, codeVerifier) {
  const config = provider(name);
  const credentials = providerCredentials(name);
  const params = new URLSearchParams({
    code,
    redirect_uri: callbackURL(req, name),
    grant_type: 'authorization_code',
    client_id: credentials.clientID,
    client_secret: credentials.clientSecret
  });
  if (codeVerifier) params.set('code_verifier', codeVerifier);

  const headers = { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' };
  if (name === 'reddit' || name === 'notion') {
    headers.authorization = `Basic ${Buffer.from(`${credentials.clientID}:${credentials.clientSecret}`).toString('base64')}`;
  }
  const response = await fetch(config.token, { method: 'POST', headers, body: params });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.error) throw new Error(`oauth_exchange_${payload.error || response.status}`);
  return payload;
}

export function publicProviderList() {
  return Object.keys(providers);
}
