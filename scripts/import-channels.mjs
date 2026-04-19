#!/usr/bin/env node
/**
 * Bulk-import checked channels from docs/channel-import.md via the admin
 * API. For each channel we:
 *   1. Hit /admin/api/channels/lookup to pull the canonical title + og:image
 *   2. POST /admin/api/channels to create the row + kick off ingest
 *
 * Throttled to one channel every 2.5s so the server's fire-and-forget
 * yt-dlp ingests don't stampede YouTube simultaneously.
 */
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from 'dotenv';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..');
config({ path: join(repoRoot, 'server/.env') });

const BASE = process.env.BASE_URL || 'http://localhost:8787';
const PASS = process.env.ADMIN_PASSWORD;
if (!PASS) { console.error('ADMIN_PASSWORD missing'); process.exit(1); }
const AUTH = 'Basic ' + Buffer.from(`admin:${PASS}`).toString('base64');
const THROTTLE_MS = 2500;

const md = await readFile(join(repoRoot, 'docs/channel-import.md'), 'utf8');
const re = /^- \[ \] \[([^\]]+)\]\((https:\/\/www\.youtube\.com\/channel\/(UC[A-Za-z0-9_-]{22}))\)/gm;
const channels = [];
for (const m of md.matchAll(re)) {
  channels.push({ title: m[1].trim(), url: m[2], id: m[3] });
}
console.log(`Parsed ${channels.length} checked channels from MD.\n`);

let created = 0, already = 0, failed = 0;
const failures = [];

for (let i = 0; i < channels.length; i++) {
  const ch = channels[i];
  const tag = `[${String(i + 1).padStart(3, ' ')}/${channels.length}]`;
  try {
    // Lookup canonical title + thumbnail (best-effort).
    let meta = null;
    try {
      const r = await fetch(`${BASE}/admin/api/channels/lookup`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: AUTH },
        body: JSON.stringify({ url: ch.url }),
      });
      if (r.ok) meta = await r.json();
    } catch {}

    const body = {
      youtube_channel_id: meta?.youtube_channel_id || ch.id,
      title: meta?.title || ch.title,
      thumbnail_url: meta?.thumbnail_url || null,
      is_active: true,
    };

    const r = await fetch(`${BASE}/admin/api/channels`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: AUTH },
      body: JSON.stringify(body),
    });

    if (r.ok) {
      created++;
      console.log(`${tag} ✓ ${body.title}`);
    } else if (r.status === 409) {
      already++;
      console.log(`${tag} - ${body.title} (already exists)`);
    } else {
      failed++;
      const err = await r.text();
      failures.push({ title: ch.title, status: r.status, err: err.slice(0, 120) });
      console.log(`${tag} ✗ ${body.title} (${r.status})`);
    }
  } catch (e) {
    failed++;
    failures.push({ title: ch.title, err: e.message });
    console.log(`${tag} ✗ ${ch.title}: ${e.message}`);
  }

  if (i < channels.length - 1) await new Promise((r) => setTimeout(r, THROTTLE_MS));
}

console.log(`\n────── done ──────`);
console.log(`created:    ${created}`);
console.log(`already:    ${already}`);
console.log(`failed:     ${failed}`);
if (failures.length) {
  console.log(`\nFailures:`);
  for (const f of failures) console.log(`  ${f.title}: ${f.status ?? 'err'} ${f.err}`);
}
