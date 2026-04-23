import type { FastifyInstance } from 'fastify';
import { pool } from '../db.js';

interface PlayableRow {
  youtube_video_id: string;
  title: string;
  thumbnail_url: string | null;
  published_at: string;
  channel_id: string;
  channel_title: string;
}

interface ProfileRow {
  id: string;
  name: string;
  position: number;
  channel_ids: string[];
}

async function loadProfile(profileId: string): Promise<ProfileRow | null> {
  const { rows } = await pool.query<ProfileRow>(
    'select id, name, position, channel_ids from profiles where id = $1',
    [profileId],
  );
  return rows[0] ?? null;
}

export async function clientRoutes(app: FastifyInstance) {
  app.get('/profiles', async () => {
    const { rows } = await pool.query<{ id: string; name: string; position: number }>(
      'select id, name, position from profiles order by position asc',
    );
    return rows;
  });

  app.get<{ Querystring: { profile?: string } }>('/playable', async (req, reply) => {
    const profileId = req.query.profile;
    if (!profileId) return reply.code(400).send({ error: 'profile query param required' });
    const profile = await loadProfile(profileId);
    if (!profile) return reply.code(404).send({ error: 'profile not found' });

    const { rows } = await pool.query<PlayableRow>(
      `select youtube_video_id, title, thumbnail_url, published_at, channel_id, channel_title
       from playable_videos
       where channel_id = any($1::uuid[])`,
      [profile.channel_ids],
    );
    return rows;
  });

  app.get<{ Querystring: { profile?: string } }>('/library', async (req, reply) => {
    const profileId = req.query.profile;
    if (!profileId) return reply.code(400).send({ error: 'profile query param required' });
    const profile = await loadProfile(profileId);
    if (!profile) return reply.code(404).send({ error: 'profile not found' });

    const channelsResult = await pool.query<{
      id: string;
      title: string;
      thumbnail_url: string | null;
      category: string | null;
      is_recommended: boolean;
    }>(
      `select id, title, thumbnail_url, category, is_recommended
       from channels
       where id = any($1::uuid[]) and is_active = true
       order by title asc`,
      [profile.channel_ids],
    );

    const videosResult = await pool.query<{
      channel_id: string;
      youtube_video_id: string;
      title: string;
      thumbnail_url: string | null;
      published_at: string;
      duration_seconds: number | null;
    }>(
      `select channel_id, youtube_video_id, title, thumbnail_url, published_at, duration_seconds
       from (
         select v.channel_id,
                v.youtube_video_id,
                v.title,
                v.thumbnail_url,
                v.published_at,
                v.duration_seconds,
                row_number() over (
                  partition by v.channel_id
                  order by
                    case when c.default_video_sort = 'oldest' then v.published_at end asc,
                    v.published_at desc
                ) as rn
         from videos v
         join channels c on v.channel_id = c.id
         where v.channel_id = any($1::uuid[])
           and c.is_active = true
           and v.is_short = false
       ) ranked
       where rn <= 80
       order by channel_id, rn`,
      [profile.channel_ids],
    );

    const byChannel = new Map<string, typeof videosResult.rows>();
    for (const v of videosResult.rows) {
      const list = byChannel.get(v.channel_id) ?? [];
      list.push(v);
      byChannel.set(v.channel_id, list);
    }

    return channelsResult.rows.map((c) => ({
      ...c,
      videos: byChannel.get(c.id) ?? [],
    }));
  });
}
