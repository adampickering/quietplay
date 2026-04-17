import { describe, it, expect, beforeAll } from 'vitest';
import Fastify from 'fastify';

// Stub pool before importing the route module
vi.mock('../src/db.js', () => ({
  pool: {
    query: vi.fn(async () => ({ rows: [], rowCount: 0 })),
  },
}));

import { vi } from 'vitest';
import { adminRoutes } from '../src/routes/admin.js';

async function makeApp() {
  const app = Fastify();
  await app.register(adminRoutes, { prefix: '/admin' });
  return app;
}

beforeAll(() => {
  process.env.ADMIN_PASSWORD = 'letmein';
});

describe('admin auth', () => {
  it('rejects unauthenticated requests with 401 and WWW-Authenticate header', async () => {
    const app = await makeApp();
    const res = await app.inject({ method: 'GET', url: '/admin/api/channels' });
    expect(res.statusCode).toBe(401);
    expect(res.headers['www-authenticate']).toMatch(/^Basic /);
  });

  it('rejects wrong password', async () => {
    const app = await makeApp();
    const auth = 'Basic ' + Buffer.from('admin:wrong').toString('base64');
    const res = await app.inject({ method: 'GET', url: '/admin/api/channels', headers: { authorization: auth } });
    expect(res.statusCode).toBe(401);
  });

  it('accepts correct password', async () => {
    const app = await makeApp();
    const auth = 'Basic ' + Buffer.from('admin:letmein').toString('base64');
    const res = await app.inject({ method: 'GET', url: '/admin/api/channels', headers: { authorization: auth } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual([]);
  });

  it('enforces position range on profile create', async () => {
    const app = await makeApp();
    const auth = 'Basic ' + Buffer.from('admin:letmein').toString('base64');
    const res = await app.inject({
      method: 'POST',
      url: '/admin/api/profiles',
      headers: { authorization: auth, 'content-type': 'application/json' },
      payload: { name: 'Kids', channel_ids: [], position: 5 },
    });
    expect(res.statusCode).toBe(400);
  });
});
