import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { request } from 'undici';
import { pool } from '../db.js';
import { categorize } from '../categorize.js';
import { ingestChannel } from '../ingest-lib.js';
import { logger } from '../logger.js';

const LOOKUP_TIMEOUT_MS = 5000;
const UC_ID = /UC[A-Za-z0-9_\-]{22}/;
const META_CHANNEL_ID_RE = /<meta\s+itemprop="(?:channelId|identifier)"\s+content="(UC[A-Za-z0-9_\-]{22})"/i;
const EXTERNAL_ID_RE = /"externalId":"(UC[A-Za-z0-9_\-]{22})"/;
const CANONICAL_RE = /<link\s+rel="canonical"\s+href="https?:\/\/www\.youtube\.com\/channel\/(UC[A-Za-z0-9_\-]{22})"/i;
const OG_TITLE_RE = /<meta\s+property="og:title"\s+content="([^"]+)"/i;
const OG_IMAGE_RE = /<meta\s+property="og:image"\s+content="([^"]+)"/i;
const DIRECT_CHANNEL_RE = /^UC[A-Za-z0-9_\-]{22}$/;

function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

async function lookupChannel(rawInput: string): Promise<{
  youtube_channel_id: string;
  title: string;
  thumbnail_url: string | null;
}> {
  const input = rawInput.trim();
  if (!input) throw new Error('empty input');

  if (DIRECT_CHANNEL_RE.test(input)) {
    return fetchChannelMeta(`https://www.youtube.com/channel/${input}`, input);
  }

  let url: URL;
  try {
    url = new URL(input);
  } catch {
    throw new Error('not a valid URL or channel ID');
  }
  if (!/(^|\.)youtube\.com$/.test(url.hostname) && url.hostname !== 'youtu.be') {
    throw new Error('not a YouTube URL');
  }

  const channelMatch = url.pathname.match(/^\/channel\/(UC[A-Za-z0-9_\-]{22})/);
  if (channelMatch) {
    return fetchChannelMeta(`https://www.youtube.com${url.pathname}`, channelMatch[1]);
  }

  return fetchChannelMeta(url.toString(), null);
}

async function fetchChannelMeta(pageUrl: string, knownId: string | null): Promise<{
  youtube_channel_id: string;
  title: string;
  thumbnail_url: string | null;
}> {
  const res = await request(pageUrl, {
    headersTimeout: LOOKUP_TIMEOUT_MS,
    bodyTimeout: LOOKUP_TIMEOUT_MS,
    maxRedirections: 5,
    headers: { 'user-agent': 'Mozilla/5.0 QuietPlayAdmin' },
  });
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw new Error(`youtube responded ${res.statusCode}`);
  }
  const body = await res.body.text();

  const id =
    knownId ??
    body.match(META_CHANNEL_ID_RE)?.[1] ??
    body.match(CANONICAL_RE)?.[1] ??
    body.match(EXTERNAL_ID_RE)?.[1];
  if (!id || !UC_ID.test(id)) throw new Error('could not find channel ID on page');

  const rawTitle = body.match(OG_TITLE_RE)?.[1];
  const rawImage = body.match(OG_IMAGE_RE)?.[1];
  const title = rawTitle ? decodeEntities(rawTitle).replace(/\s*-\s*YouTube$/, '').trim() : id;
  const thumbnail_url = rawImage ? decodeEntities(rawImage) : null;

  return { youtube_channel_id: id, title, thumbnail_url };
}

const here = dirname(fileURLToPath(import.meta.url));
const htmlPath = join(here, '..', 'admin', 'index.html');

interface ChannelRow {
  id: string;
  youtube_channel_id: string;
  title: string;
  thumbnail_url: string | null;
  is_active: boolean;
  default_video_sort: 'newest' | 'oldest';
  category: string | null;
  is_recommended: boolean;
  created_at: string;
}

interface ProfileRow {
  id: string;
  name: string;
  channel_ids: string[];
  position: number;
}

function requireAuth(req: FastifyRequest, reply: FastifyReply): boolean {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) {
    reply.code(500).send({ error: 'ADMIN_PASSWORD not configured' });
    return false;
  }
  const header = req.headers.authorization;
  if (!header?.startsWith('Basic ')) {
    reply.header('WWW-Authenticate', 'Basic realm="QuietPlay Admin"').code(401).send();
    return false;
  }
  let decoded: string;
  try {
    decoded = Buffer.from(header.slice(6), 'base64').toString('utf8');
  } catch {
    reply.code(401).send();
    return false;
  }
  const sep = decoded.indexOf(':');
  const pass = sep >= 0 ? decoded.slice(sep + 1) : decoded;
  if (pass !== expected) {
    reply.header('WWW-Authenticate', 'Basic realm="QuietPlay Admin"').code(401).send();
    return false;
  }
  return true;
}

export async function adminRoutes(app: FastifyInstance) {
  app.addHook('onRequest', async (req, reply) => {
    if (!requireAuth(req, reply)) return reply;
  });

  app.get('/', async (_req, reply) => {
    const html = await readFile(htmlPath, 'utf8');
    return reply.type('text/html; charset=utf-8').send(html);
  });

  // Channel URL → metadata lookup
  app.post<{ Body: { url: string } }>('/api/channels/lookup', async (req, reply) => {
    const { url } = req.body ?? ({} as { url: string });
    if (!url?.trim()) return reply.code(400).send({ error: 'url required' });
    try {
      const meta = await lookupChannel(url);
      return meta;
    } catch (err) {
      return reply.code(400).send({ error: err instanceof Error ? err.message : 'lookup failed' });
    }
  });

  // Channels
  app.get('/api/channels', async () => {
    const { rows } = await pool.query<ChannelRow>(
      'select * from channels order by title asc',
    );
    return rows;
  });

  app.post<{
    Body: {
      youtube_channel_id: string;
      title: string;
      thumbnail_url?: string | null;
      is_active?: boolean;
      default_video_sort?: 'newest' | 'oldest';
      category?: string | null;
    };
  }>('/api/channels', async (req, reply) => {
    const { youtube_channel_id, title, thumbnail_url, is_active, default_video_sort, category } = req.body;
    if (!youtube_channel_id?.trim() || !title?.trim()) {
      return reply.code(400).send({ error: 'youtube_channel_id and title are required' });
    }
    if (default_video_sort && !['newest', 'oldest'].includes(default_video_sort)) {
      return reply.code(400).send({ error: 'default_video_sort must be newest or oldest' });
    }
    // Auto-categorize from the title when the admin doesn't set one.
    // Parent can override later via PATCH.
    const resolvedCategory = (category ?? categorize(title)).trim();
    try {
      const { rows } = await pool.query<ChannelRow>(
        `insert into channels (youtube_channel_id, title, thumbnail_url, is_active, default_video_sort, category)
         values ($1, $2, $3, coalesce($4, true), coalesce($5, 'newest'), $6)
         returning *`,
        [
          youtube_channel_id.trim(),
          title.trim(),
          thumbnail_url ?? null,
          is_active ?? null,
          default_video_sort ?? null,
          resolvedCategory,
        ],
      );
      const created = rows[0];
      // Fire-and-forget ingest for the newly-added channel so the first
      // 15 videos land in the library without waiting for the hourly
      // cron. Doesn't block the HTTP response.
      ingestChannel({ id: created.id, youtube_channel_id: created.youtube_channel_id })
        .then((r) => {
          logger.info({ channel: created.youtube_channel_id, ...r }, 'post-create ingest');
        })
        .catch((err) => {
          logger.warn({ err, channel: created.youtube_channel_id }, 'post-create ingest failed');
        });
      return created;
    } catch (err: any) {
      if (err?.code === '23505') {
        return reply.code(409).send({ error: 'channel already exists' });
      }
      throw err;
    }
  });

  app.patch<{
    Params: { id: string };
    Body: {
      title?: string;
      thumbnail_url?: string | null;
      is_active?: boolean;
      default_video_sort?: 'newest' | 'oldest';
      category?: string | null;
      is_recommended?: boolean;
    };
  }>('/api/channels/:id', async (req, reply) => {
    const { id } = req.params;
    const { title, thumbnail_url, is_active, default_video_sort, category, is_recommended } = req.body;
    if (default_video_sort && !['newest', 'oldest'].includes(default_video_sort)) {
      return reply.code(400).send({ error: 'default_video_sort must be newest or oldest' });
    }
    const { rows } = await pool.query<ChannelRow>(
      `update channels
         set title = coalesce($2, title),
             thumbnail_url = coalesce($3, thumbnail_url),
             is_active = coalesce($4, is_active),
             default_video_sort = coalesce($5, default_video_sort),
             category = coalesce($6, category),
             is_recommended = coalesce($7, is_recommended)
       where id = $1
       returning *`,
      [
        id,
        title ?? null,
        thumbnail_url ?? null,
        is_active ?? null,
        default_video_sort ?? null,
        category ?? null,
        is_recommended ?? null,
      ],
    );
    if (rows.length === 0) return reply.code(404).send({ error: 'not found' });
    return rows[0];
  });

  // Profiles
  app.get('/api/profiles', async () => {
    const { rows } = await pool.query<ProfileRow>(
      'select id, name, channel_ids, position from profiles order by position asc',
    );
    return rows;
  });

  app.post<{
    Body: { name: string; channel_ids: string[]; position: number };
  }>('/api/profiles', async (req, reply) => {
    const { name, channel_ids, position } = req.body;
    if (!name?.trim()) return reply.code(400).send({ error: 'name required' });
    if (!Array.isArray(channel_ids)) return reply.code(400).send({ error: 'channel_ids must be array' });
    if (!Number.isInteger(position) || position < 0 || position > 2) {
      return reply.code(400).send({ error: 'position must be 0, 1, or 2' });
    }

    const { rows: existing } = await pool.query<{ count: string }>(
      'select count(*)::text as count from profiles',
    );
    if (Number(existing[0].count) >= 3) {
      return reply.code(409).send({ error: 'max 3 profiles' });
    }

    try {
      const { rows } = await pool.query<ProfileRow>(
        `insert into profiles (name, channel_ids, position)
         values ($1, $2::uuid[], $3)
         returning id, name, channel_ids, position`,
        [name.trim(), channel_ids, position],
      );
      return rows[0];
    } catch (err: any) {
      if (err?.code === '23505') {
        return reply.code(409).send({ error: 'position already taken' });
      }
      throw err;
    }
  });

  app.patch<{
    Params: { id: string };
    Body: { name?: string; channel_ids?: string[]; position?: number };
  }>('/api/profiles/:id', async (req, reply) => {
    const { id } = req.params;
    const { name, channel_ids, position } = req.body;
    if (position !== undefined && (!Number.isInteger(position) || position < 0 || position > 2)) {
      return reply.code(400).send({ error: 'position must be 0, 1, or 2' });
    }
    try {
      const { rows } = await pool.query<ProfileRow>(
        `update profiles
           set name = coalesce($2, name),
               channel_ids = coalesce($3::uuid[], channel_ids),
               position = coalesce($4, position)
         where id = $1
         returning id, name, channel_ids, position`,
        [id, name ?? null, channel_ids ?? null, position ?? null],
      );
      if (rows.length === 0) return reply.code(404).send({ error: 'not found' });
      return rows[0];
    } catch (err: any) {
      if (err?.code === '23505') {
        return reply.code(409).send({ error: 'position already taken' });
      }
      throw err;
    }
  });

  app.delete<{ Params: { id: string } }>('/api/profiles/:id', async (req, reply) => {
    const { rowCount } = await pool.query('delete from profiles where id = $1', [req.params.id]);
    if (rowCount === 0) return reply.code(404).send({ error: 'not found' });
    return reply.code(204).send();
  });
}
