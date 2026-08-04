import test from 'node:test';
import assert from 'node:assert/strict';
import { publicProviderList, provider } from '../lib/providers.js';
import { actionCatalog } from '../lib/executor.js';

test('provider registry and action catalog stay aligned', () => {
  for (const name of publicProviderList()) {
    assert.ok(provider(name));
    assert.ok(Array.isArray(actionCatalog[name]));
  }
});
