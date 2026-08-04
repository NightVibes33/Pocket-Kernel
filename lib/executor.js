import { getConnection } from './connections.js';

function assertString(value, name, max = 20000) {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new Error(`invalid_${name}`);
  return value.trim();
}

async function providerRequest(url, token, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json', ...(options.headers || {}) }
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok || body?.ok === false) throw new Error(`provider_${response.status}_${body?.error || 'error'}`);
  return body;
}

export const actionCatalog = {
  google: ['gmail.list', 'gmail.send', 'calendar.create'],
  slack: ['message.send'],
  discord: ['webhook.send'],
  reddit: ['post.create'],
  notion: ['page.create']
};

export async function executeServiceAction(userID, provider, action, input) {
  if (!actionCatalog[provider]?.includes(action)) throw new Error('unsupported_action');
  const connection = await getConnection(userID, provider);
  if (!connection) throw new Error('service_not_connected');
  const token = connection.tokens.access_token || connection.tokens.bot?.bot_access_token;
  if (!token) throw new Error('missing_access_token');

  if (provider === 'google' && action === 'gmail.list') {
    const query = encodeURIComponent(input.query || 'in:inbox');
    return providerRequest(`https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=20&q=${query}`, token);
  }
  if (provider === 'google' && action === 'gmail.send') {
    const to = assertString(input.to, 'to', 320);
    const subject = assertString(input.subject, 'subject', 998);
    const body = assertString(input.body, 'body');
    const raw = Buffer.from(`To: ${to}\r\nSubject: ${subject}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n${body}`).toString('base64url');
    return providerRequest('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', token, { method: 'POST', body: JSON.stringify({ raw }) });
  }
  if (provider === 'google' && action === 'calendar.create') {
    const summary = assertString(input.summary, 'summary', 1000);
    const start = new Date(input.start);
    const end = new Date(input.end);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end <= start) throw new Error('invalid_dates');
    return providerRequest('https://www.googleapis.com/calendar/v3/calendars/primary/events', token, {
      method: 'POST', body: JSON.stringify({ summary, description: input.description || '', start: { dateTime: start.toISOString() }, end: { dateTime: end.toISOString() } })
    });
  }
  if (provider === 'slack' && action === 'message.send') {
    return providerRequest('https://slack.com/api/chat.postMessage', token, { method: 'POST', body: JSON.stringify({ channel: assertString(input.channel, 'channel', 200), text: assertString(input.text, 'text') }) });
  }
  if (provider === 'discord' && action === 'webhook.send') {
    const webhook = connection.tokens.webhook?.url;
    if (!webhook) throw new Error('missing_discord_webhook');
    const response = await fetch(webhook, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ content: assertString(input.text, 'text') }) });
    if (!response.ok) throw new Error(`provider_${response.status}`);
    return { ok: true };
  }
  if (provider === 'reddit' && action === 'post.create') {
    const params = new URLSearchParams({ api_type: 'json', kind: 'self', sr: assertString(input.subreddit, 'subreddit', 100), title: assertString(input.title, 'title', 300), text: assertString(input.text, 'text') });
    const response = await fetch('https://oauth.reddit.com/api/submit', { method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/x-www-form-urlencoded', 'user-agent': 'PocketKernel/2.0' }, body: params });
    const body = await response.json();
    if (!response.ok || body?.json?.errors?.length) throw new Error('provider_reddit_error');
    return body;
  }
  if (provider === 'notion' && action === 'page.create') {
    return providerRequest('https://api.notion.com/v1/pages', token, {
      method: 'POST',
      headers: { 'Notion-Version': '2022-06-28' },
      body: JSON.stringify({ parent: { page_id: assertString(input.parentPageID, 'parentPageID', 100) }, properties: { title: { title: [{ text: { content: assertString(input.title, 'title', 1000) } }] } }, children: [{ object: 'block', type: 'paragraph', paragraph: { rich_text: [{ type: 'text', text: { content: String(input.body || '') } }] } }] })
    });
  }
  throw new Error('unsupported_action');
}
