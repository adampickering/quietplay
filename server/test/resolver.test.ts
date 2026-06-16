import { describe, it, expect, beforeEach, vi } from 'vitest';

vi.mock('../src/redis.js', () => {
  const store = new Map<string, string>();
  return {
    redis: {
      get: vi.fn(async (k: string) => store.get(k) ?? null),
      set: vi.fn(async (k: string, v: string) => {
        store.set(k, v);
        return 'OK';
      }),
      __store: store,
    },
  };
});

import Fastify from 'fastify';
import { resolverRoutes } from '../src/routes/resolver.js';
import { redis } from '../src/redis.js';

const runnerOk = { resolve: vi.fn(async () => 'https://googlevideo.example/stream.mp4') };
const runnerFail = { resolve: vi.fn(async () => { throw new Error('boom'); }) };

async function makeApp(runner: { resolve: (id: string) => Promise<string> }) {
  const app = Fastify();
  await app.register(resolverRoutes(runner));
  return app;
}

beforeEach(() => {
  (redis as any).__store.clear();
  runnerOk.resolve.mockClear();
  runnerFail.resolve.mockClear();
});

describe('resolver', () => {
  it('returns ok payload and caches it', async () => {
    const app = await makeApp(runnerOk);
    const r1 = await app.inject({ method: 'GET', url: '/resolve/aaaaaaaaaaa' });
    expect(r1.statusCode).toBe(200);
    const body1 = r1.json();
    expect(body1.status).toBe('ok');
    expect(body1.streamUrl).toMatch(/^https:/);
    expect(runnerOk.resolve).toHaveBeenCalledTimes(1);

    const r2 = await app.inject({ method: 'GET', url: '/resolve/aaaaaaaaaaa' });
    expect(r2.json().streamUrl).toBe(body1.streamUrl);
    expect(runnerOk.resolve).toHaveBeenCalledTimes(1);
  });

  it('caches failures separately', async () => {
    const app = await makeApp(runnerFail);
    const r1 = await app.inject({ method: 'GET', url: '/resolve/bbbbbbbbbbb' });
    expect(r1.json().status).toBe('error');
    const r2 = await app.inject({ method: 'GET', url: '/resolve/bbbbbbbbbbb' });
    expect(r2.json().status).toBe('error');
    expect(runnerFail.resolve).toHaveBeenCalledTimes(1);
  });

  it('serves a near-expiry cache hit and revalidates in the background', async () => {
    const fresh = vi.fn(async () => 'https://googlevideo.example/new.mp4');
    const app = await makeApp({ resolve: fresh });
    const stale = {
      status: 'ok',
      streamUrl: 'https://googlevideo.example/old.mp4',
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      error: null,
    };
    (redis as any).__store.set('resolve:ok:ccccccccccc', JSON.stringify(stale));

    const r = await app.inject({ method: 'GET', url: '/resolve/ccccccccccc' });
    expect(r.json().streamUrl).toBe(stale.streamUrl);

    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(fresh).toHaveBeenCalledTimes(1);
    const stored = JSON.parse((redis as any).__store.get('resolve:ok:ccccccccccc'));
    expect(stored.streamUrl).toBe('https://googlevideo.example/new.mp4');
  });
});
