#!/usr/bin/env node
/**
 * One-off fixer: walks every video in the DB, asks yt-dlp for the
 * real YouTube upload_date via a single-video extract (flat-playlist
 * sometimes returns non-upload timestamps for channel tabs), and
 * corrects published_at.
 *
 * Slow — ~500ms per video. Expect ~15–25 min for a 6k library.
 * Run from repo root:  node scripts/fix-dates.mjs
 */
import pg from '/Users/adam/dev/quietplay/node_modules/pg/lib/index.js';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileP = promisify(execFile);
const pool = new pg.Pool({ connectionString: 'postgres://quietplay:quietplay@localhost:5432/quietplay' });
const CONCURRENCY = 3;

const { rows } = await pool.query(
  `select id, youtube_video_id, title from videos order by ingested_at desc`,
);
console.log(`Fixing dates for ${rows.length} videos (concurrency ${CONCURRENCY})...`);

let done = 0, changed = 0, skipped = 0;
const start = Date.now();

async function fixOne(row) {
  try {
    const { stdout } = await execFileP(
      'yt-dlp',
      ['--skip-download', '--no-warnings', '-O', '%(upload_date)s',
       `https://youtu.be/${row.youtube_video_id}`],
      { timeout: 20_000 },
    );
    const ud = stdout.trim();
    if (!/^\d{8}$/.test(ud)) { skipped++; return; }
    const iso = `${ud.slice(0, 4)}-${ud.slice(4, 6)}-${ud.slice(6, 8)}T12:00:00Z`;
    const { rowCount } = await pool.query(
      `update videos set published_at = $1
       where id = $2 and published_at::date <> $3::date`,
      [iso, row.id, iso],
    );
    if (rowCount > 0) changed++;
  } catch {
    skipped++;
  } finally {
    done++;
    if (done % 100 === 0) {
      const elapsed = ((Date.now() - start) / 1000).toFixed(0);
      const rate = (done / (Date.now() - start) * 1000).toFixed(1);
      console.log(`  ${done}/${rows.length} · changed ${changed} · skipped ${skipped} · ${elapsed}s · ${rate}/s`);
    }
  }
}

for (let i = 0; i < rows.length; i += CONCURRENCY) {
  await Promise.all(rows.slice(i, i + CONCURRENCY).map(fixOne));
}

console.log(`\nDone. Changed ${changed}, skipped ${skipped}, total ${done}.`);
await pool.end();
