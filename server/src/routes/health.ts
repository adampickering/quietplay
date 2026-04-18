import type { FastifyInstance } from 'fastify';
import { pool } from '../db.js';
import { redis } from '../redis.js';

const startedAt = Date.now();

export async function healthRoutes(app: FastifyInstance) {
  app.get('/healthz', async (_req, reply) => {
    let dbOk = false;
    let redisOk = false;
    let dbError: string | null = null;
    let redisError: string | null = null;

    try {
      await pool.query('select 1');
      dbOk = true;
    } catch (err) {
      dbError = err instanceof Error ? err.message : 'unknown';
    }

    try {
      const pong = await redis.ping();
      redisOk = pong === 'PONG';
      if (!redisOk) redisError = `unexpected reply: ${pong}`;
    } catch (err) {
      redisError = err instanceof Error ? err.message : 'unknown';
    }

    const status = dbOk && redisOk ? 200 : 503;
    return reply.code(status).send({
      status: dbOk && redisOk ? 'ok' : 'degraded',
      db: dbOk ? 'ok' : dbError,
      redis: redisOk ? 'ok' : redisError,
      uptime_seconds: Math.floor((Date.now() - startedAt) / 1000),
    });
  });
}
