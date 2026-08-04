import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const files = [];
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.js')) files.push(full);
  }
}
walk(path.join(root, 'api'));
walk(path.join(root, 'lib'));
if (!files.length) throw new Error('No backend files found');

const requiredFiles = [
  'api/auth/apple.js',
  'api/auth/email/signup.js',
  'api/auth/email/signin.js',
  'api/auth/google/start.js',
  'api/auth/google/callback.js',
  'api/auth/exchange.js',
  'lib/account.js',
  'lib/oidc.js'
];
for (const relative of requiredFiles) {
  if (!fs.existsSync(path.join(root, relative))) throw new Error(`Missing production account route: ${relative}`);
}

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  if (/CLIENT_SECRET\s*=\s*['"][^'"]+/.test(text) || /TOKEN_ENCRYPTION_KEY\s*=/.test(text)) {
    throw new Error(`Hardcoded secret in ${file}`);
  }
  const check = spawnSync(process.execPath, ['--check', file], { encoding: 'utf8' });
  if (check.status !== 0) throw new Error(`Syntax error in ${file}:\n${check.stderr || check.stdout}`);
}

console.log(`Validated ${files.length} backend modules, production account routes, syntax, and secret boundaries.`);
