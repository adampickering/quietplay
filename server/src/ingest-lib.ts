// Pure-function ingest primitives, importable from the admin route so
// that creating a new channel can kick off a one-shot fetch for that
// channel without shelling out to `node dist/ingest.js`.
//
// The hourly cron job goes through ingestAll() below.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { pool } from './db.js';

const execFileP = promisify(execFile);

const MAX_ENTRIES = 500;
const CONCURRENCY = 2;
const FEED_TIMEOUT_MS = 30_000;

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

/// YouTube defines Shorts as <=60s + vertical, but duration alone
/// catches ~95% of them and costs nothing — the old HEAD-to-/shorts/
/// trick stopped working (YouTube started returning 200 for everything)
/// so we were flagging zero shorts across 88 channels after the last
/// re-ingest. Treat anything <=60s as a short.
export function isShortByDuration(durationSeconds: number | null): boolean {
  return durationSeconds !== null && durationSeconds > 0 && durationSeconds <= 60;
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
      '--print',
      '%(id)s\t%(title)s\t%(timestamp)s\t%(upload_date)s\t%(thumbnail)s\t%(duration)s',
      url,
    ],
    { timeout: FEED_TIMEOUT_MS, maxBuffer: 10 * 1024 * 1024 },
  );

  const lines = stdout.split('\n').filter((l) => l.length > 0);
  const entries: FeedEntry[] = [];
  const now = Date.now();
  for (let i = 0; i < lines.length; i++) {
    const [id, title, tsStr, uploadStr, thumb, durStr] = lines[i].split('\t');
    if (!id || !/^[A-Za-z0-9_-]{11}$/.test(id)) continue;

    // Prefer the unix timestamp; fall back to YouTube's upload_date
    // (YYYYMMDD); if BOTH are NA (common for some newer channels in
    // flat-playlist mode) fall back to a position-based placeholder
    // so rows still get inserted. The nightly date-fix script runs a
    // full yt-dlp extract per video and corrects the real dates later.
    const published = parseDate(tsStr, uploadStr)
      ?? new Date(now - i * 86_400_000).toISOString();

    const durNum = durStr && durStr !== 'NA' ? Math.round(Number(durStr)) : NaN;
    entries.push({
      youtube_video_id: id,
      title: title ?? '',
      thumbnail_url: thumb && thumb !== 'NA' ? thumb : `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
      published_at: published,
      duration_seconds: Number.isFinite(durNum) && durNum > 0 ? durNum : null,
    });
  }
  return entries;
}

/** timestamp (unix seconds) wins; upload_date (YYYYMMDD) is the backup
 *  because yt-dlp's YouTube extractor sometimes populates one but not
 *  the other depending on how the channel listing was cached. */
function parseDate(tsStr: string | undefined, uploadStr: string | undefined): string | null {
  if (tsStr && tsStr !== 'NA') {
    const n = Number(tsStr);
    if (Number.isFinite(n) && n > 0) {
      return new Date(n * 1000).toISOString();
    }
  }
  if (uploadStr && uploadStr !== 'NA' && /^\d{8}$/.test(uploadStr)) {
    const y = Number(uploadStr.slice(0, 4));
    const m = Number(uploadStr.slice(4, 6));
    const d = Number(uploadStr.slice(6, 8));
    const date = new Date(Date.UTC(y, m - 1, d));
    if (!Number.isNaN(date.getTime())) return date.toISOString();
  }
  return null;
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
      duration_seconds = coalesce(excluded.duration_seconds, videos.duration_seconds),
      published_at = excluded.published_at,
      title = excluded.title,
      thumbnail_url = excluded.thumbnail_url
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
    const enriched: EnrichedEntry[] = entries.map((e) => ({
      ...e,
      is_short: isShortByDuration(e.duration_seconds),
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
