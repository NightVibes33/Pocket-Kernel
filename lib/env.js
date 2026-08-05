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
  const oauthProviders = ['GOOGLE', 'SLACK', 'DISCORD', 'REDDIT', 'NOTION'];
  const providers = Object.fromEntries(
    oauthProviders.map((provider) => [
      provider.toLowerCase(),
      Boolean(process.env[`${provider}_CLIENT_ID`] && process.env[`${provider}_CLIENT_SECRET`])
    ])
  );

  providers.apple = Boolean(process.env.APPLE_CLIENT_ID || 'com.nightvibes33.pocketkernel');
  providers.email = Boolean(process.env.RESEND_API_KEY && process.env.EMAIL_FROM);

  return {
    redis: Boolean(process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN),
    sessionSecret: Boolean(process.env.SESSION_SECRET),
    tokenEncryption: Boolean(process.env.TOKEN_ENCRYPTION_KEY),
    providers
  };
}
