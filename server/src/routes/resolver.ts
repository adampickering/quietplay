import type { FastifyInstance } from 'fastify';
import { redis } from '../redis.js';
import { defaultRunner, type YtDlpRunner, ResolveError } from '../ytdlp.js';
import { logger } from '../logger.js';

const OK_TTL = 4 * 60 * 60;
const FAIL_TTL = 15 * 60;
// 2 is deliberate — bumping higher triggers YouTube IP-level rate
// limiting, after which even sequential resolves slow from ~15s to
// 80–100s for several minutes. Verified by experiment: 6 parallel
// resolves throttled this Mac's IP so badly that a single subsequent
// direct yt-dlp call took 97s. Don't raise without confirming YouTube
// behaviour for this account/IP first.
const MAX_CONCURRENT_RESOLVES = 2;

const inflight = new Map<string, Promise<string>>();
let active = 0;
const waitQueue: Array<() => void> = [];

function acquireSlot(): Promise<void> {
  if (active < MAX_CONCURRENT_RESOLVES) {
    active++;
    return Promise.resolve();
  }
  return new Promise((resolve) => waitQueue.push(resolve));
}

function releaseSlot() {
  const next = waitQueue.shift();
  if (next) next();
  else active--;
}

interface OkPayload {
  status: 'ok';
  streamUrl: string;
  expiresAt: string;
  error: null;
}

interface ErrPayload {
  status: 'error';
  streamUrl: null;
  expiresAt: null;
  error: string;
}

type Payload = OkPayload | ErrPayload;

export function resolverRoutes(runner: YtDlpRunner = defaultRunner) {
  return async function register(app: FastifyInstance) {
    app.get<{ Params: { id: string } }>('/resolve/:id', async (req, reply) => {
      const { id } = req.params;
      const start = Date.now();

      const okKey = `resolve:ok:${id}`;
      const failKey = `resolve:fail:${id}`;

      const cachedOk = await redis.get(okKey);
      if (cachedOk) {
        logger.info({ videoId: id, status: 'ok', duration_ms: Date.now() - start, cache_hit: true });
        return reply.send(JSON.parse(cachedOk) as Payload);
      }
      const cachedFail = await redis.get(failKey);
      if (cachedFail) {
        logger.info({ videoId: id, status: 'error', duration_ms: Date.now() - start, cache_hit: true });
        return reply.send(JSON.parse(cachedFail) as Payload);
      }

      try {
        let resolvePromise = inflight.get(id);
        if (!resolvePromise) {
          resolvePromise = (async () => {
            await acquireSlot();
            try {
              return await runner.resolve(id);
            } finally {
              releaseSlot();
            }
          })();
          inflight.set(id, resolvePromise);
          resolvePromise.then(
            () => inflight.delete(id),
            () => inflight.delete(id),
          );
        }
        const streamUrl = await resolvePromise;
        const expiresAt = new Date(Date.now() + OK_TTL * 1000).toISOString();
        const payload: OkPayload = { status: 'ok', streamUrl, expiresAt, error: null };
        await redis.set(okKey, JSON.stringify(payload), 'EX', OK_TTL);
        logger.info({ videoId: id, status: 'ok', duration_ms: Date.now() - start, cache_hit: false });
        return reply.send(payload);
      } catch (err) {
        const message = err instanceof ResolveError ? err.message : 'unknown error';
        const payload: ErrPayload = { status: 'error', streamUrl: null, expiresAt: null, error: message };
        await redis.set(failKey, JSON.stringify(payload), 'EX', FAIL_TTL);
        logger.info({ videoId: id, status: 'error', duration_ms: Date.now() - start, cache_hit: false, error: message });
        return reply.send(payload);
      }
    });
  };
}
