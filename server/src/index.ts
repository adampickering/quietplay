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

async function main() {
  // Fail fast if Postgres is unreachable. Without this check the server
  // starts happily, binds the port, and only errors on the first
  // request — which looks like a mystery 500 in the admin UI.
  try {
    await pool.query('select 1');
  } catch (err) {
    logger.error({ err }, 'database unreachable at startup');
    throw err;
  }

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
