import 'dotenv/config';
import { ingestAll } from './ingest-lib.js';
import { pool } from './db.js';
import { logger } from './logger.js';

async function main() {
  const summary = await ingestAll();
  logger.info(summary);
  await pool.end();
}

main().catch((err) => {
  logger.error({ err }, 'ingest failed');
  process.exit(1);
});
