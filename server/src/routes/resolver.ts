import type { FastifyInstance } from 'fastify';
import { defaultRunner, type YtDlpRunner } from '../ytdlp.js';
import { resolveWithCache } from '../resolverService.js';
import { logger } from '../logger.js';

export function resolverRoutes(runner: YtDlpRunner = defaultRunner) {
  return async function register(app: FastifyInstance) {
    app.get<{ Params: { id: string } }>('/resolve/:id', async (req, reply) => {
      const { id } = req.params;
      const start = Date.now();
      const { payload, cacheHit } = await resolveWithCache(id, runner);
      const base = {
        videoId: id,
        status: payload.status,
        duration_ms: Date.now() - start,
        cache_hit: cacheHit,
      };
      if (payload.status === 'error') {
        logger.info({ ...base, error: payload.error });
      } else {
        logger.info(base);
      }
      return reply.send(payload);
    });
  };
}
