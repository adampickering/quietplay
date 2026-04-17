import 'dotenv/config';
import Fastify from 'fastify';
import { resolverRoutes } from './routes/resolver.js';
import { clientRoutes } from './routes/client.js';
import { adminRoutes } from './routes/admin.js';
import { logger } from './logger.js';

async function main() {
  const app = Fastify({ loggerInstance: logger });

  await app.register(resolverRoutes());
  await app.register(clientRoutes);
  await app.register(adminRoutes, { prefix: '/admin' });

  const port = Number(process.env.PORT ?? 3000);
  await app.listen({ port, host: '0.0.0.0' });
}

main().catch((err) => {
  logger.error({ err }, 'server failed to start');
  process.exit(1);
});
