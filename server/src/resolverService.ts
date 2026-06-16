import { redis } from './redis.js';
import { defaultRunner, type YtDlpRunner, ResolveError } from './ytdlp.js';
import { logger } from './logger.js';

const OK_TTL = 4 * 60 * 60;
const FAIL_TTL = 15 * 60;
// SWR: re-resolve in the background once a cached OK has this little
// time left. Headroom over yt-dlp's ~20–45s worst case.
const SWR_REVALIDATE_THRESHOLD_MS = 20 * 60 * 1000;
// 2 is deliberate — bumping higher triggers YouTube IP-level rate
// limiting, after which even sequential resolves slow from ~15s to
// 80–100s for several minutes. Verified by experiment: 6 parallel
// resolves throttled this Mac's IP so badly that a single subsequent
// direct yt-dlp call took 97s. Don't raise without confirming YouTube
// behaviour for this account/IP first.
const MAX_CONCURRENT_RESOLVES = 2;

const inflight = new Map<string, Promise<string>>();
let active = 0;
let foregroundActive = 0;
const fgWaitQueue: Array<() => void> = [];
const bgWaitQueue: Array<() => void> = [];

function acquireSlot(priority: 'foreground' | 'background' = 'foreground'): Promise<void> {
  if (active < MAX_CONCURRENT_RESOLVES) {
    active++;
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    if (priority === 'foreground') fgWaitQueue.push(resolve);
    else bgWaitQueue.push(resolve);
  });
}

function releaseSlot() {
  const next = fgWaitQueue.shift() ?? bgWaitQueue.shift();
  if (next) next();
  else active--;
}

async function waitForForegroundDrain(): Promise<void> {
  while (foregroundActive > 0) {
    await new Promise<void>((r) => setTimeout(r, 250));
  }
}

export interface OkPayload {
  status: 'ok';
  streamUrl: string;
  expiresAt: string;
  error: null;
}

export interface ErrPayload {
  status: 'error';
  streamUrl: null;
  expiresAt: null;
  error: string;
}

export type Payload = OkPayload | ErrPayload;

export interface ResolveResult {
  payload: Payload;
  cacheHit: boolean;
}

const revalidating = new Set<string>();

function revalidateInBackground(id: string, runner: YtDlpRunner): void {
  if (revalidating.has(id) || inflight.has(id)) return;
  revalidating.add(id);
  void (async () => {
    await waitForForegroundDrain();
    const start = Date.now();
    await acquireSlot('background');
    try {
      const streamUrl = await runner.resolve(id);
      const expiresAt = new Date(Date.now() + OK_TTL * 1000).toISOString();
      const payload: OkPayload = { status: 'ok', streamUrl, expiresAt, error: null };
      await redis.set(`resolve:ok:${id}`, JSON.stringify(payload), 'EX', OK_TTL);
      logger.info({ videoId: id, source: 'swr', duration_ms: Date.now() - start });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'unknown';
      logger.warn({ videoId: id, source: 'swr', err: message }, 'background revalidate failed');
    } finally {
      releaseSlot();
      revalidating.delete(id);
    }
  })();
}

export async function resolveWithCache(
  id: string,
  runner: YtDlpRunner,
  source: 'foreground' | 'background' = 'foreground',
): Promise<ResolveResult> {
  const okKey = `resolve:ok:${id}`;
  const failKey = `resolve:fail:${id}`;

  const cachedOk = await redis.get(okKey);
  if (cachedOk) {
    const payload = JSON.parse(cachedOk) as Payload;
    if (payload.status === 'ok' && payload.expiresAt) {
      const msLeft = new Date(payload.expiresAt).getTime() - Date.now();
      if (msLeft > 0 && msLeft < SWR_REVALIDATE_THRESHOLD_MS) {
        revalidateInBackground(id, runner);
      }
    }
    return { payload, cacheHit: true };
  }
  const cachedFail = await redis.get(failKey);
  if (cachedFail) return { payload: JSON.parse(cachedFail) as Payload, cacheHit: true };

  if (source === 'foreground') foregroundActive++;
  try {
    let resolvePromise = inflight.get(id);
    if (!resolvePromise) {
      resolvePromise = (async () => {
        await acquireSlot(source);
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
    return { payload, cacheHit: false };
  } catch (err) {
    const message = err instanceof ResolveError ? err.message : 'unknown error';
    const payload: ErrPayload = { status: 'error', streamUrl: null, expiresAt: null, error: message };
    await redis.set(failKey, JSON.stringify(payload), 'EX', FAIL_TTL);
    return { payload, cacheHit: false };
  } finally {
    if (source === 'foreground') foregroundActive--;
  }
}

// Pre-warm queue: drained one resolve at a time so the foreground
// always has the second yt-dlp slot free. Cached and in-flight ids are
// skipped before taking a slot — a foreground click for the same video
// will piggyback on the in-flight resolve via the inflight Map above.
const preWarmQueue: string[] = [];
const preWarmQueued = new Set<string>();
let preWarmRunning = false;

async function drainPreWarm(): Promise<void> {
  while (preWarmQueue.length > 0) {
    await waitForForegroundDrain();
    const id = preWarmQueue.shift()!;
    preWarmQueued.delete(id);
    try {
      if (await redis.get(`resolve:ok:${id}`)) continue;
      if (await redis.get(`resolve:fail:${id}`)) continue;
      const start = Date.now();
      const { cacheHit } = await resolveWithCache(id, defaultRunner, 'background');
      logger.info({ videoId: id, source: 'prewarm', duration_ms: Date.now() - start, cache_hit: cacheHit });
    } catch (err) {
      logger.warn({ videoId: id, source: 'prewarm', err }, 'pre-warm resolve failed');
    }
  }
  preWarmRunning = false;
}

export function enqueuePreWarm(ids: string[]): void {
  let added = false;
  for (const id of ids) {
    if (preWarmQueued.has(id)) continue;
    preWarmQueue.push(id);
    preWarmQueued.add(id);
    added = true;
  }
  if (added && !preWarmRunning) {
    preWarmRunning = true;
    void drainPreWarm();
  }
}
