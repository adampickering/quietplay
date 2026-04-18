// Pure-function ingest primitives, importable from the admin route so
// that creating a new channel can kick off a one-shot fetch for that
// channel without shelling out to `node dist/ingest.js`.
//
// The hourly cron job goes through ingestAll() below.

import { request } from 'undici';
import { XMLParser } from 'fast-xml-parser';
import { pool } from './db.js';

const MAX_ENTRIES = 15;
const CONCURRENCY = 4;
const SHORTS_CHECK_CONCURRENCY = 8;
const FEED_TIMEOUT_MS = 10_000;
const SHORTS_CHECK_TIMEOUT_MS = 4_000;

export interface Channel {
  id: string;
  youtube_channel_id: string;
}

export interface FeedEntry {
  youtube_video_id: string;
  title: string;
  thumbnail_url: string | null;
  published_at: string;
}

export interface EnrichedEntry extends FeedEntry {
  is_short: boolean;
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
});

export async function isShort(videoID: string): Promise<boolean> {
  try {
    const res = await request(`https://www.youtube.com/shorts/${videoID}`, {
      headersTimeout: SHORTS_CHECK_TIMEOUT_MS,
      bodyTimeout: SHORTS_CHECK_TIMEOUT_MS,
      maxRedirections: 0,
      headers: { 'user-agent': 'Mozilla/5.0 QuietPlayBot' },
    });
    await res.body.dump();
    return res.statusCode === 200;
  } catch {
    return false;
  }
}

export async function fetchFeed(youtubeChannelId: string): Promise<FeedEntry[]> {
  const url = `https://www.youtube.com/feeds/videos.xml?channel_id=${youtubeChannelId}`;
  const res = await request(url, {
    headersTimeout: FEED_TIMEOUT_MS,
    bodyTimeout: FEED_TIMEOUT_MS,
    headers: { 'user-agent': 'Mozilla/5.0 QuietPlayBot' },
  });
  if (res.statusCode !== 200) {
    throw new Error(`feed ${youtubeChannelId} status ${res.statusCode}`);
  }
  const body = await res.body.text();
  const parsed = parser.parse(body);
  const entries = parsed?.feed?.entry;
  if (!entries) return [];
  const arr = Array.isArray(entries) ? entries : [entries];
  return arr.slice(0, MAX_ENTRIES).map((e: any) => ({
    youtube_video_id: e['yt:videoId'],
    title: typeof e.title === 'string' ? e.title : e.title?.['#text'] ?? '',
    thumbnail_url: e['media:group']?.['media:thumbnail']?.['@_url'] ?? null,
    published_at: e.published,
  }));
}

export async function upsertVideos(
  channelId: string,
  entries: EnrichedEntry[],
): Promise<{ added: number; shorts: number }> {
  if (entries.length === 0) return { added: 0, shorts: 0 };
  const values: unknown[] = [];
  const tuples: string[] = [];
  entries.forEach((e, i) => {
    const base = i * 6;
    tuples.push(`($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6})`);
    values.push(channelId, e.youtube_video_id, e.title, e.thumbnail_url, e.published_at, e.is_short);
  });
  const sql = `
    insert into videos (channel_id, youtube_video_id, title, thumbnail_url, published_at, is_short)
    values ${tuples.join(', ')}
    on conflict (youtube_video_id) do update set is_short = excluded.is_short
  `;
  const result = await pool.query(sql, values);
  const shorts = entries.filter((e) => e.is_short).length;
  return { added: result.rowCount ?? 0, shorts };
}

async function runPool<T, R>(
  items: T[],
  limit: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  async function runOne() {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await worker(items[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, runOne));
  return results;
}

export async function processChannel(
  channel: Channel,
): Promise<{ added: number; shorts: number; error?: string }> {
  try {
    const entries = await fetchFeed(channel.youtube_channel_id);
    const enriched = await runPool(entries, SHORTS_CHECK_CONCURRENCY, async (e) => ({
      ...e,
      is_short: await isShort(e.youtube_video_id),
    }));
    const { added, shorts } = await upsertVideos(channel.id, enriched);
    return { added, shorts };
  } catch (err) {
    return { added: 0, shorts: 0, error: err instanceof Error ? err.message : String(err) };
  }
}

/**
 * One-shot ingest for a single channel. Called from the admin route
 * after a new channel is inserted so the first batch of videos shows
 * up in the library without waiting for the hourly cron.
 */
export async function ingestChannel(channel: Channel) {
  return processChannel(channel);
}

/**
 * Full hourly ingest over every active channel. Called from the cron
 * script (dist/ingest.js).
 */
export async function ingestAll() {
  const start = Date.now();
  const { rows: channels } = await pool.query<Channel>(
    'select id, youtube_channel_id from channels where is_active = true',
  );
  const results = await runPool(channels, CONCURRENCY, processChannel);
  const videos_added = results.reduce((sum, r) => sum + r.added, 0);
  const shorts_flagged = results.reduce((sum, r) => sum + r.shorts, 0);
  const errors = results
    .map((r, i) => (r.error ? { channel: channels[i].youtube_channel_id, error: r.error } : null))
    .filter((x): x is { channel: string; error: string } => x !== null);

  return {
    channels_processed: channels.length,
    videos_added,
    shorts_flagged,
    duration_ms: Date.now() - start,
    errors,
  };
}
