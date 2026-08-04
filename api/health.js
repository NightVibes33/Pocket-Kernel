import { configuration } from '../lib/env.js';
import { json } from '../lib/http.js';

export default function handler(req, res) {
  json(res, 200, {
    name: 'PocketKernel Automation API',
    version: '2.0.0',
    status: 'ok',
    ai: 'none — all planning runs with Apple Foundation Models on the iPhone',
    configuration: configuration(),
    time: new Date().toISOString()
  });
}
