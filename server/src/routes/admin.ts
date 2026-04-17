import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { pool } from '../db.js';

const here = dirname(fileURLToPath(import.meta.url));
const htmlPath = join(here, '..', 'admin', 'index.html');

interface ChannelRow {
  id: string;
  youtube_channel_id: string;
  title: string;
  thumbnail_url: string | null;
  is_active: boolean;
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
    };
  }>('/api/channels', async (req, reply) => {
    const { youtube_channel_id, title, thumbnail_url, is_active } = req.body;
    if (!youtube_channel_id?.trim() || !title?.trim()) {
      return reply.code(400).send({ error: 'youtube_channel_id and title are required' });
    }
    try {
      const { rows } = await pool.query<ChannelRow>(
        `insert into channels (youtube_channel_id, title, thumbnail_url, is_active)
         values ($1, $2, $3, coalesce($4, true))
         returning *`,
        [youtube_channel_id.trim(), title.trim(), thumbnail_url ?? null, is_active ?? null],
      );
      return rows[0];
    } catch (err: any) {
      if (err?.code === '23505') {
        return reply.code(409).send({ error: 'channel already exists' });
      }
      throw err;
    }
  });

  app.patch<{
    Params: { id: string };
    Body: { title?: string; thumbnail_url?: string | null; is_active?: boolean };
  }>('/api/channels/:id', async (req, reply) => {
    const { id } = req.params;
    const { title, thumbnail_url, is_active } = req.body;
    const { rows } = await pool.query<ChannelRow>(
      `update channels
         set title = coalesce($2, title),
             thumbnail_url = coalesce($3, thumbnail_url),
             is_active = coalesce($4, is_active)
       where id = $1
       returning *`,
      [id, title ?? null, thumbnail_url ?? null, is_active ?? null],
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
