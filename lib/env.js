export function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`missing_${name}`);
  return value;
}

export function baseURL(req) {
  if (process.env.PUBLIC_BASE_URL) return process.env.PUBLIC_BASE_URL.replace(/\/$/, '');
  const proto = req.headers['x-forwarded-proto'] || 'https';
  const host = req.headers['x-forwarded-host'] || req.headers.host;
  return `${proto}://${host}`;
}

export function configuration() {
  const providers = ['GOOGLE', 'SLACK', 'DISCORD', 'REDDIT', 'NOTION'];
  return {
    redis: Boolean(process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN),
    sessionSecret: Boolean(process.env.SESSION_SECRET),
    tokenEncryption: Boolean(process.env.TOKEN_ENCRYPTION_KEY),
    providers: Object.fromEntries(providers.map((p) => [p.toLowerCase(), Boolean(process.env[`${p}_CLIENT_ID`] && process.env[`${p}_CLIENT_SECRET`])]))
  };
}
