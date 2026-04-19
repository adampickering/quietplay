// Pure-function ingest primitives, importable from the admin route so
// that creating a new channel can kick off a one-shot fetch for that
// channel without shelling out to `node dist/ingest.js`.
//
// The hourly cron job goes through ingestAll() below.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { request } from 'undici';
import { pool } from './db.js';

const execFileP = promisify(execFile);

const MAX_ENTRIES = 80;
const CONCURRENCY = 4;
const SHORTS_CHECK_CONCURRENCY = 8;
const FEED_TIMEOUT_MS = 30_000;
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
  /// Whole seconds. Null when yt-dlp didn't include one in the
  /// flat-playlist entry (live streams, some older uploads).
  duration_seconds: number | null;
}

export interface EnrichedEntry extends FeedEntry {
  is_short: boolean;
}

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

/**
 * Enumerate up to MAX_ENTRIES newest uploads for a channel via yt-dlp's
 * flat-playlist mode. RSS would be faster but caps at ~15 entries; flat
 * mode returns one JSON line per video without fetching each page.
 *
 * `timestamp` (upload epoch seconds) is included by yt-dlp's YouTube
 * extractor in recent versions. When absent we fall back to a
 * position-based synthetic date so list ordering stays stable — the
 * channel listing is already newest-first.
 */
export async function fetchChannelVideos(youtubeChannelId: string): Promise<FeedEntry[]> {
  const url = `https://www.youtube.com/channel/${youtubeChannelId}/videos`;
  const { stdout } = await execFileP(
    'yt-dlp',
    [
      '--flat-playlist',
      '--playlist-end', String(MAX_ENTRIES),
      '--no-warnings',
      '--print', '%(id)s\t%(title)s\t%(timestamp)s\t%(thumbnail)s\t%(duration)s',
      url,
    ],
    { timeout: FEED_TIMEOUT_MS, maxBuffer: 10 * 1024 * 1024 },
  );

  const now = Date.now();
  const lines = stdout.split('\n').filter((l) => l.length > 0);
  const entries: FeedEntry[] = [];
  for (let i = 0; i < lines.length; i++) {
    const [id, title, tsStr, thumb, durStr] = lines[i].split('\t');
    if (!id || !/^[A-Za-z0-9_-]{11}$/.test(id)) continue;
    const tsNum = tsStr && tsStr !== 'NA' ? Number(tsStr) : NaN;
    const publishedMs = Number.isFinite(tsNum) ? tsNum * 1000 : now - i * 86_400_000;
    const durNum = durStr && durStr !== 'NA' ? Math.round(Number(durStr)) : NaN;
    entries.push({
      youtube_video_id: id,
      title: title ?? '',
      thumbnail_url: thumb && thumb !== 'NA' ? thumb : `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
      published_at: new Date(publishedMs).toISOString(),
      duration_seconds: Number.isFinite(durNum) && durNum > 0 ? durNum : null,
    });
  }
  return entries;
}

async function getExistingShortsFlags(
  channelId: string,
  videoIds: string[],
): Promise<Map<string, boolean>> {
  if (videoIds.length === 0) return new Map();
  const { rows } = await pool.query<{ youtube_video_id: string; is_short: boolean }>(
    'select youtube_video_id, is_short from videos where channel_id = $1 and youtube_video_id = any($2::text[])',
    [channelId, videoIds],
  );
  return new Map(rows.map((r) => [r.youtube_video_id, r.is_short]));
}

export async function upsertVideos(
  channelId: string,
  entries: EnrichedEntry[],
): Promise<{ added: number; shorts: number }> {
  if (entries.length === 0) return { added: 0, shorts: 0 };
  const values: unknown[] = [];
  const tuples: string[] = [];
  entries.forEach((e, i) => {
    const base = i * 7;
    tuples.push(
      `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}, $${base + 7})`,
    );
    values.push(
      channelId,
      e.youtube_video_id,
      e.title,
      e.thumbnail_url,
      e.published_at,
      e.is_short,
      e.duration_seconds,
    );
  });
  // Update duration on conflict too: yt-dlp occasionally returns NA on
  // an earlier pass and fills it in on a later one, and we'd rather the
  // thumbnail badge light up late than never.
  const sql = `
    insert into videos (channel_id, youtube_video_id, title, thumbnail_url, published_at, is_short, duration_seconds)
    values ${tuples.join(', ')}
    on conflict (youtube_video_id) do update set
      is_short = excluded.is_short,
      duration_seconds = coalesce(excluded.duration_seconds, videos.duration_seconds)
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
    const entries = await fetchChannelVideos(channel.youtube_channel_id);
    const existing = await getExistingShortsFlags(
      channel.id,
      entries.map((e) => e.youtube_video_id),
    );
    // Only pay the is_short HEAD request for videos we haven't seen
    // before. With 80 entries × N channels per hour, reusing stored
    // flags keeps us well under YouTube's rate limits.
    const enriched = await runPool(entries, SHORTS_CHECK_CONCURRENCY, async (e) => {
      const cached = existing.get(e.youtube_video_id);
      return {
        ...e,
        is_short: cached ?? (await isShort(e.youtube_video_id)),
      };
    });
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
