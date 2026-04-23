import type { FastifyInstance } from 'fastify';
import { pool } from '../db.js';
import { logger } from '../logger.js';

interface EventPayload {
  profile_id: string;
  events: Array<{
    youtube_video_id?: string;
    event_type?: string;   // defaults to 'watch'
    seconds?: number;
  }>;
}

/**
 * Client telemetry sink. Kids' device batches watch-seconds per video
 * every ~60s; this route resolves youtube_video_id → videos.id and
 * appends to watch_events. No admin auth — LAN-only, writes are
 * append-only, and the client has to already know a valid profile_id.
 */
export async function eventRoutes(app: FastifyInstance) {
  app.post<{ Body: EventPayload }>('/events/watch', async (req, reply) => {
    const { profile_id, events } = req.body ?? ({} as EventPayload);
    if (!profile_id || !Array.isArray(events) || events.length === 0) {
      return reply.code(400).send({ error: 'profile_id + events required' });
    }
    if (events.length > 500) {
      return reply.code(413).send({ error: 'too many events in one batch' });
    }

    // Validate profile exists (cheap sanity check so junk clients don't
    // stuff the table with garbage).
    const { rows: profiles } = await pool.query<{ id: string }>(
      'select id from profiles where id = $1',
      [profile_id],
    );
    if (profiles.length === 0) {
      return reply.code(404).send({ error: 'profile not found' });
    }

    // Resolve youtube_video_id → videos.id in one go.
    const ytIds = events
      .map((e) => e.youtube_video_id)
      .filter((x): x is string => typeof x === 'string' && x.length > 0);
    const videoMap = new Map<string, string>();
    if (ytIds.length > 0) {
      const { rows } = await pool.query<{ id: string; youtube_video_id: string }>(
        'select id, youtube_video_id from videos where youtube_video_id = any($1::text[])',
        [ytIds],
      );
      for (const r of rows) videoMap.set(r.youtube_video_id, r.id);
    }

    const values: unknown[] = [];
    const tuples: string[] = [];
    let kept = 0;
    for (const e of events) {
      const videoId = e.youtube_video_id ? videoMap.get(e.youtube_video_id) ?? null : null;
      const eventType = (e.event_type || 'watch').slice(0, 32);
      const seconds = typeof e.seconds === 'number' && e.seconds > 0
        ? Math.min(3600, Math.round(e.seconds))
        : null;
      if (eventType === 'watch' && (seconds === null || videoId === null)) continue;
      const base = kept * 4;
      tuples.push(`($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4})`);
      values.push(profile_id, videoId, eventType, seconds);
      kept++;
    }
    if (kept === 0) {
      return reply.code(200).send({ accepted: 0, ignored: events.length });
    }

    const sql = `
      insert into watch_events (profile_id, video_id, event_type, seconds)
      values ${tuples.join(', ')}
    `;
    try {
      await pool.query(sql, values);
    } catch (err) {
      logger.warn({ err }, 'watch_events insert failed');
      return reply.code(500).send({ error: 'db write failed' });
    }
    return { accepted: kept, ignored: events.length - kept };
  });
}
