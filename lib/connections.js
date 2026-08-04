import { decryptJSON, encryptJSON } from './crypto.js';
import { deleteKey, getJSON, putJSON, redis } from './redis.js';

const key = (userID, provider) => `pk:connection:${userID}:${provider}`;
const indexKey = (userID) => `pk:connections:${userID}`;

export async function saveConnection(userID, provider, tokens) {
  const record = {
    provider,
    encrypted: encryptJSON(tokens),
    connectedAt: new Date().toISOString(),
    expiresAt: tokens.expires_in ? new Date(Date.now() + Number(tokens.expires_in) * 1000).toISOString() : null
  };
  await putJSON(key(userID, provider), record);
  await redis('SADD', indexKey(userID), provider);
  return { provider, connectedAt: record.connectedAt, expiresAt: record.expiresAt };
}

export async function getConnection(userID, provider) {
  const record = await getJSON(key(userID, provider));
  if (!record) return null;
  return { ...record, tokens: decryptJSON(record.encrypted) };
}

export async function listConnections(userID) {
  const names = (await redis('SMEMBERS', indexKey(userID))) || [];
  const records = await Promise.all(names.map(async (name) => {
    const record = await getJSON(key(userID, name));
    return record ? { provider: name, connectedAt: record.connectedAt, expiresAt: record.expiresAt } : null;
  }));
  return records.filter(Boolean);
}

export async function removeConnection(userID, provider) {
  await deleteKey(key(userID, provider));
  await redis('SREM', indexKey(userID), provider);
}
