import 'dotenv/config';
import { request } from 'undici';
import { XMLParser } from 'fast-xml-parser';
import { pool } from './db.js';
import { logger } from './logger.js';

const MAX_ENTRIES = 15;
const CONCURRENCY = 4;
const FEED_TIMEOUT_MS = 10_000;

interface Channel {
  id: string;
  youtube_channel_id: string;
}

interface FeedEntry {
  youtube_video_id: string;
  title: string;
  thumbnail_url: string | null;
  published_at: string;
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
});

async function fetchFeed(youtubeChannelId: string): Promise<FeedEntry[]> {
  const url = `https://www.youtube.com/feeds/videos.xml?channel_id=${youtubeChannelId}`;
  const res = await request(url, { headersTimeout: FEED_TIMEOUT_MS, bodyTimeout: FEED_TIMEOUT_MS });
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

async function upsertVideos(channelId: string, entries: FeedEntry[]): Promise<number> {
  if (entries.length === 0) return 0;
  const values: unknown[] = [];
  const tuples: string[] = [];
  entries.forEach((e, i) => {
    const base = i * 5;
    tuples.push(`($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5})`);
    values.push(channelId, e.youtube_video_id, e.title, e.thumbnail_url, e.published_at);
  });
  const sql = `
    insert into videos (channel_id, youtube_video_id, title, thumbnail_url, published_at)
    values ${tuples.join(', ')}
    on conflict (youtube_video_id) do nothing
  `;
  const result = await pool.query(sql, values);
  return result.rowCount ?? 0;
}

async function processChannel(channel: Channel): Promise<{ added: number; error?: string }> {
  try {
    const entries = await fetchFeed(channel.youtube_channel_id);
    const added = await upsertVideos(channel.id, entries);
    return { added };
  } catch (err) {
    return { added: 0, error: err instanceof Error ? err.message : String(err) };
  }
}

async function runPool<T, R>(items: T[], limit: number, worker: (item: T) => Promise<R>): Promise<R[]> {
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

async function main() {
  const start = Date.now();
  const { rows: channels } = await pool.query<Channel>(
    'select id, youtube_channel_id from channels where is_active = true',
  );

  const results = await runPool(channels, CONCURRENCY, processChannel);

  const videos_added = results.reduce((sum, r) => sum + r.added, 0);
  const errors = results
    .map((r, i) => (r.error ? { channel: channels[i].youtube_channel_id, error: r.error } : null))
    .filter((x): x is { channel: string; error: string } => x !== null);

  logger.info({
    channels_processed: channels.length,
    videos_added,
    duration_ms: Date.now() - start,
    errors,
  });

  await pool.end();
}

main().catch((err) => {
  logger.error({ err }, 'ingest failed');
  process.exit(1);
});
