import 'dotenv/config';
import Fastify from 'fastify';
import { pool } from './db.js';
import { resolverRoutes } from './routes/resolver.js';
import { clientRoutes } from './routes/client.js';
import { adminRoutes } from './routes/admin.js';
import { healthRoutes } from './routes/health.js';
import { eventRoutes } from './routes/events.js';
import { dashboardRoutes } from './routes/dashboard.js';
import { logger } from './logger.js';

// Wait for Postgres before binding the port. On a cold boot the server
// races Docker Postgres coming up; retry for ~60s so we survive the race
// but still fail fast if the DB is genuinely down (otherwise the server
// binds the port and only errors on the first request — a mystery 500).
async function waitForDatabase(timeoutMs = 60_000, intervalMs = 2_000) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    try {
      await pool.query('select 1');
      return;
    } catch (err) {
      if (Date.now() >= deadline) {
        logger.error({ err }, 'database unreachable at startup');
        throw err;
      }
      logger.warn('database not ready, retrying…');
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
  }
}

async function main() {
  await waitForDatabase();

  const app = Fastify({ loggerInstance: logger });

  await app.register(healthRoutes);
  await app.register(resolverRoutes());
  await app.register(clientRoutes);
  await app.register(eventRoutes);
  await app.register(adminRoutes, { prefix: '/admin' });
  await app.register(dashboardRoutes, { prefix: '/admin' });

  const port = Number(process.env.PORT ?? 8787);
  await app.listen({ port, host: '0.0.0.0' });
}

main().catch((err) => {
  logger.error({ err }, 'server failed to start');
  process.exit(1);
});
