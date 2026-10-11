import { timingSafeEqual } from 'node:crypto';
const LOOPBACK = new Set(['127.0.0.1', '::1', 'localhost']);
export function accessPolicy(env = process.env) {
  const host = env.DEVTOOLS_HOST || '127.0.0.1';
  const token = env.DEVTOOLS_TOKEN || '';
  if (!LOOPBACK.has(host) && token.length < 32) {
    throw new Error('LAN devtools requires an explicitly configured DEVTOOLS_TOKEN (at least 32 characters).');
  }
  return { host, token };
}
export function allowedRequest(req, policy) {
  // Reject browser cross-origin requests, including DNS-rebinding hostnames.
  const host = req.headers.host || '';
  const hostname = host.startsWith('[') ? host.slice(1, host.indexOf(']')) : host.split(':')[0];
  if (LOOPBACK.has(policy.host) && !LOOPBACK.has(hostname)) return false;
  if (req.headers.origin && req.headers.origin !== `http://${host}`) return false;
  if (req.headers['sec-fetch-site'] === 'cross-site') return false;
  if (!policy.token) return true;
  // Bearer for API clients; Basic for native browser authentication prompts.
  // Never accept a token in a URL, where it would enter logs/history.
  const authorization = req.headers.authorization || '';
  let provided = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (authorization.startsWith('Basic ')) {
    const decoded = Buffer.from(authorization.slice(6), 'base64').toString('utf8');
    provided = decoded.slice(decoded.indexOf(':') + 1);
  }
  const a = Buffer.from(provided), b = Buffer.from(policy.token);
  return a.length === b.length && timingSafeEqual(a, b);
}
