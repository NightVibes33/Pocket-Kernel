import fs from 'node:fs';
import path from 'node:path';

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
for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  if (/CLIENT_SECRET\s*=\s*['"][^'"]+/.test(text) || /TOKEN_ENCRYPTION_KEY\s*=/.test(text)) throw new Error(`Hardcoded secret in ${file}`);
}
console.log(`Validated ${files.length} backend modules; no hardcoded credentials.`);
